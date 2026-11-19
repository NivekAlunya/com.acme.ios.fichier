//
//  TVVideoSeekThumbnailCoordinator.swift
//  FichierTV
//

import AVFoundation
import UIKit
import Observation
import FichierKit

/// Coordinator managing seek-preview thumbnail extraction, LRU bucket caching, and background worker loops.
@Observable
@MainActor
public final class TVVideoSeekThumbnailCoordinator {
    /// Active preview thumbnail state surfaced to the scrubber and HUD views.
    public var seekThumbnailState: TVSeekThumbnailState?

    private var thumbnailWorkerTask: Task<Void, Never>?
    private var latestThumbnailRequest: TVSeekThumbnailRequest?
    private var latestThumbnailBucket: Double?
    private var cachedBucketImages: [Int: UIImage] = [:]
    private var cachedBucketOrder: [Int] = []
    private var assetRegistrationTask: Task<Void, Never>?
    private let thumbnailProvider: any TVSeekThumbnailProviding

    public init(thumbnailProvider: any TVSeekThumbnailProviding = TVSeekThumbnailService()) {
        self.thumbnailProvider = thumbnailProvider
    }

    public func clearState() {
        seekThumbnailState = nil
    }

    public func registerAsset(_ asset: AVURLAsset, forAssetKey assetKey: String) {
        assetRegistrationTask?.cancel()
        assetRegistrationTask = Task { [thumbnailProvider] in
            await thumbnailProvider.registerAsset(asset, forAssetKey: assetKey)
        }
    }

    public func reset(forAssetKey assetKey: String) {
        cancelSeekThumbnails(clearState: true)
        cachedBucketImages.removeAll()
        cachedBucketOrder.removeAll()
        assetRegistrationTask?.cancel()
        assetRegistrationTask = Task { [thumbnailProvider] in
            await thumbnailProvider.invalidateAsset(forAssetKey: assetKey)
        }
    }

    public func cancelSeekThumbnails(clearState: Bool) {
        thumbnailWorkerTask?.cancel()
        thumbnailWorkerTask = nil
        latestThumbnailRequest = nil
        latestThumbnailBucket = nil
        if clearState {
            seekThumbnailState = nil
        } else if let currentState = seekThumbnailState {
            seekThumbnailState = TVSeekThumbnailState(
                targetTime: currentState.targetTime,
                bucketTime: currentState.bucketTime,
                image: currentState.image,
                isLoading: false
            )
        }
    }

    public func requestSeekThumbnail(
        for targetTime: Double,
        duration: Double,
        assetKey: String,
        targetURL: URL?,
        engineKind: PlayerEngineKind,
        vlcOptions: VLCPlaybackOptions?,
        activeTargetProvider: @escaping @MainActor () -> Double?
    ) {
        guard let targetURL else { return }

        let safeDuration = duration
        let bucket = TVSeekThumbnailService.bucketTimestamp(targetTime: targetTime, duration: safeDuration)
        let bucketKey = Int(bucket.rounded())
        let request = TVSeekThumbnailRequest(
            url: targetURL,
            assetKey: assetKey,
            targetTime: targetTime,
            duration: safeDuration,
            engineKind: engineKind,
            vlcOptions: vlcOptions
        )

        latestThumbnailRequest = request
        latestThumbnailBucket = bucket

        if let cachedImage = cachedBucketImages[bucketKey] {
            seekThumbnailState = TVSeekThumbnailState(
                targetTime: targetTime,
                bucketTime: bucket,
                image: cachedImage,
                isLoading: false
            )
            return
        }

        seekThumbnailState = TVSeekThumbnailState(
            targetTime: targetTime,
            bucketTime: bucket,
            image: seekThumbnailState?.image,
            isLoading: true
        )

        if thumbnailWorkerTask == nil {
            thumbnailWorkerTask = Task { [weak self] in
                await self?.runThumbnailWorkerLoop(
                    engineKind: engineKind,
                    duration: duration,
                    activeTargetProvider: activeTargetProvider
                )
            }
        }
    }

    private func runThumbnailWorkerLoop(
        engineKind: PlayerEngineKind,
        duration: Double,
        activeTargetProvider: @MainActor () -> Double?
    ) async {
        let settleDuration: Duration = engineKind == .extended ? .milliseconds(140) : .milliseconds(75)
        try? await Task.sleep(for: settleDuration)

        while !Task.isCancelled {
            guard let request = latestThumbnailRequest else {
                break
            }
            let targetBucket = TVSeekThumbnailService.bucketTimestamp(
                targetTime: request.targetTime,
                duration: request.duration
            )
            let bucketKey = Int(targetBucket.rounded())
            latestThumbnailRequest = nil

            if let cachedImage = cachedBucketImages[bucketKey] {
                if !Task.isCancelled, activeTargetProvider() != nil,
                   latestThumbnailBucket == targetBucket {
                    seekThumbnailState = TVSeekThumbnailState(
                        targetTime: activeTargetProvider() ?? request.targetTime,
                        bucketTime: targetBucket,
                        image: cachedImage,
                        isLoading: false
                    )
                }
                continue
            }

            let decoded = await thumbnailProvider.generateThumbnail(for: request)
            guard !Task.isCancelled else { break }

            if let decoded {
                storeCachedBucketImage(decoded, forBucketKey: bucketKey)
            }

            if let activeTarget = activeTargetProvider() {
                let activeBucket = TVSeekThumbnailService.bucketTimestamp(targetTime: activeTarget, duration: duration)
                if activeBucket == targetBucket {
                    seekThumbnailState = TVSeekThumbnailState(
                        targetTime: activeTarget,
                        bucketTime: targetBucket,
                        image: decoded,
                        isLoading: false
                    )
                } else if let decoded {
                    seekThumbnailState = TVSeekThumbnailState(
                        targetTime: activeTarget,
                        bucketTime: activeBucket,
                        image: decoded,
                        isLoading: true
                    )
                }
            }

            if latestThumbnailRequest != nil {
                let cooldownDuration: Duration
                if request.engineKind == .extended && !request.url.isFileURL {
                    cooldownDuration = .milliseconds(300)
                } else {
                    cooldownDuration = .milliseconds(60)
                }
                try? await Task.sleep(for: cooldownDuration)
            }
        }

        thumbnailWorkerTask = nil
    }

    private func storeCachedBucketImage(_ image: UIImage, forBucketKey key: Int) {
        if cachedBucketImages[key] == nil {
            cachedBucketOrder.append(key)
            if cachedBucketOrder.count > 48, let evicted = cachedBucketOrder.first {
                cachedBucketOrder.removeFirst()
                cachedBucketImages.removeValue(forKey: evicted)
            }
        }
        cachedBucketImages[key] = image
    }
}
