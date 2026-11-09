//
//  TVSeekThumbnailProviding.swift
//  FichierTV
//
//

import UIKit

/// Abstraction generating and caching quantized preview frames for timeline scrubbing and remote holds.
public protocol TVSeekThumbnailProviding: Sendable {
    func cachedThumbnail(for request: TVSeekThumbnailRequest) async -> UIImage?
    func generateThumbnail(for request: TVSeekThumbnailRequest) async -> UIImage?
    func invalidateAsset(forAssetKey assetKey: String) async
}
