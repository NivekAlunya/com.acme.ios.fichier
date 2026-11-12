//
//  TVSeekThumbnailService.swift
//  FichierTV
//
//

import AVFoundation
import FichierKit
import UIKit

/// Actor generating, quantizing, and caching on-demand seek preview thumbnails for `AVPlayer` and `VLCKit`.
public actor TVSeekThumbnailService: TVSeekThumbnailProviding {
    private let cache: NSCache<NSString, UIImage> = {
        let storage = NSCache<NSString, UIImage>()
        storage.countLimit = 48
        storage.totalCostLimit = 18 * 1024 * 1024
        return storage
    }()

    private var cachedKeysByAsset: [String: Set<String>] = [:]
    private var cachedAssets: [String: (url: URL, asset: AVURLAsset)] = [:]

    public init() {}

    /// Snaps an arbitrary target timestamp to a bounded bucket cadence to avoid redundant SMB decodes.
    public nonisolated static func bucketTimestamp(targetTime: Double, duration: Double) -> Double {
        guard targetTime.isFinite, !targetTime.isNaN else {
            return 0
        }

        let hasValidDuration = duration.isFinite && !duration.isNaN && duration > 0
        let upperBound: Double
        if hasValidDuration {
            upperBound = duration > 1.0 ? max(0, duration - 0.5) : duration
        } else {
            upperBound = max(0, targetTime)
        }

        let clamped = min(upperBound, max(0, targetTime))
        let interval = hasValidDuration ? max(2.0, min(30.0, (duration / 120.0).rounded())) : 2.0
        let snapped = (clamped / interval).rounded() * interval
        if hasValidDuration && snapped > upperBound {
            return max(0, (upperBound / interval).rounded(.down) * interval)
        }
        return max(0, snapped)
    }

    public func cachedThumbnail(for request: TVSeekThumbnailRequest) async -> UIImage? {
        let key = Self.cacheKey(for: request)
        return cache.object(forKey: key as NSString)
    }

    public func generateThumbnail(for request: TVSeekThumbnailRequest) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        let bucket = Self.bucketTimestamp(targetTime: request.targetTime, duration: request.duration)
        let key = Self.cacheKey(for: request, bucket: bucket)
        if let existing = cache.object(forKey: key as NSString) {
            return existing
        }

        let decoded: UIImage?
        switch request.engineKind {
        case .native:
            let asset = urlAsset(for: request)
            if let avImage = await Self.extractNativeFrame(
                asset: asset,
                targetTime: bucket,
                maxDimension: request.maxDimension,
                timeoutSeconds: request.url.isFileURL ? 2.5 : 4.5
            ) {
                decoded = avImage
            } else if !Task.isCancelled {
                decoded = await Self.extractExtendedFrame(
                    url: request.url,
                    targetTime: bucket,
                    duration: request.duration,
                    maxDimension: request.maxDimension,
                    options: request.vlcOptions
                )
            } else {
                decoded = nil
            }

        case .extended:
            decoded = await Self.extractExtendedFrame(
                url: request.url,
                targetTime: bucket,
                duration: request.duration,
                maxDimension: request.maxDimension,
                options: request.vlcOptions
            )
        }

        guard let decoded, !Task.isCancelled else {
            return nil
        }

        let cost = Int(decoded.size.width * decoded.size.height * 4)
        cache.setObject(decoded, forKey: key as NSString, cost: max(1, cost))
        cachedKeysByAsset[request.assetKey, default: []].insert(key)
        return decoded
    }

    public func registerAsset(_ asset: AVURLAsset, forAssetKey assetKey: String) async {
        cachedAssets[assetKey] = (asset.url, asset)
    }

    public func invalidateAsset(forAssetKey assetKey: String) async {
        cachedAssets.removeValue(forKey: assetKey)
        if let keys = cachedKeysByAsset.removeValue(forKey: assetKey) {
            for key in keys {
                cache.removeObject(forKey: key as NSString)
            }
        }
    }

    private func urlAsset(for request: TVSeekThumbnailRequest) -> AVURLAsset {
        if let cached = cachedAssets[request.assetKey], cached.url == request.url {
            return cached.asset
        }
        let asset = AVURLAsset(
            url: request.url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        cachedAssets[request.assetKey] = (request.url, asset)
        return asset
    }

    private static func cacheKey(for request: TVSeekThumbnailRequest, bucket: Double? = nil) -> String {
        let resolvedBucket = bucket ?? bucketTimestamp(targetTime: request.targetTime, duration: request.duration)
        return "\(request.assetKey)|\(request.engineKind.rawValue)|b:\(Int(resolvedBucket.rounded()))|\(Int(request.maxDimension.rounded()))"
    }

    private nonisolated static func extractNativeFrame(
        asset: AVURLAsset,
        targetTime: Double,
        maxDimension: CGFloat,
        timeoutSeconds: Double
    ) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        return await withTaskGroup(of: UIImage?.self) { group in
            group.addTask {
                guard !Task.isCancelled else { return nil }
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
                generator.requestedTimeToleranceBefore = .positiveInfinity
                generator.requestedTimeToleranceAfter = .positiveInfinity

                let cmTime = CMTime(seconds: max(0, targetTime), preferredTimescale: 600)
                if let (cgImage, _) = try? await generator.image(at: cmTime) {
                    return UIImage(cgImage: cgImage)
                }
                return nil
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return nil
            }

            let firstResult = (await group.next()).flatMap { $0 }
            group.cancelAll()
            return firstResult
        }
    }

    private nonisolated static func extractExtendedFrame(
        url: URL,
        targetTime: Double,
        duration: Double,
        maxDimension: CGFloat,
        options: VLCPlaybackOptions? = nil
    ) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let ratio = (duration.isFinite && duration > 0) ? Float(min(0.95, max(0.0, targetTime / duration))) : 0.05
        return await VLCVideoThumbnailActor.shared.generateThumbnail(
            from: url,
            maxDimension: maxDimension,
            snapshotPosition: ratio,
            timeoutSeconds: 5.5,
            snapshotTimeSeconds: targetTime,
            options: options
        )
    }
}
