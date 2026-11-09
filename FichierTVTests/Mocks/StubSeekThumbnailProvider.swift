//
//  StubSeekThumbnailProvider.swift
//  FichierTVTests
//
//

import UIKit
import FichierKit
@testable import FichierTV

public actor StubSeekThumbnailProvider: TVSeekThumbnailProviding {
    public private(set) var generatedRequests: [TVSeekThumbnailRequest] = []
    public private(set) var invalidatedKeys: [String] = []
    private var cachedByKey: [String: UIImage] = [:]
    private let delayNanoseconds: UInt64
    private let stubImage: UIImage

    public init(delayNanoseconds: UInt64 = 0, stubImage: UIImage? = nil) {
        self.delayNanoseconds = delayNanoseconds
        if let stubImage {
            self.stubImage = stubImage
        } else {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 36))
            self.stubImage = renderer.image { context in
                UIColor.systemOrange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
            }
        }
    }

    public func cachedThumbnail(for request: TVSeekThumbnailRequest) async -> UIImage? {
        cachedByKey[cacheKey(for: request)]
    }

    public func generateThumbnail(for request: TVSeekThumbnailRequest) async -> UIImage? {
        generatedRequests.append(request)
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard !Task.isCancelled else { return nil }
        cachedByKey[cacheKey(for: request)] = stubImage
        return stubImage
    }

    public func invalidateAsset(forAssetKey assetKey: String) async {
        invalidatedKeys.append(assetKey)
        cachedByKey = cachedByKey.filter { !$0.key.hasPrefix("\(assetKey)|") }
    }

    public func requestCount() -> Int {
        generatedRequests.count
    }

    private func cacheKey(for request: TVSeekThumbnailRequest) -> String {
        let bucket = TVSeekThumbnailService.bucketTimestamp(targetTime: request.targetTime, duration: request.duration)
        return "\(request.assetKey)|\(request.engineKind.rawValue)|b:\(Int(bucket.rounded()))"
    }
}
