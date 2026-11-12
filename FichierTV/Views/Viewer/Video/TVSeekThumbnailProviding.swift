//
//  TVSeekThumbnailProviding.swift
//  FichierTV
//
//

import AVFoundation
import UIKit

/// Abstraction generating and caching quantized preview frames for timeline scrubbing and remote holds.
public protocol TVSeekThumbnailProviding: Sendable {
    func cachedThumbnail(for request: TVSeekThumbnailRequest) async -> UIImage?
    func generateThumbnail(for request: TVSeekThumbnailRequest) async -> UIImage?
    func registerAsset(_ asset: AVURLAsset, forAssetKey assetKey: String) async
    func invalidateAsset(forAssetKey assetKey: String) async
}
