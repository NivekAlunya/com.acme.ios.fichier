//
//  MediaCacheManager+MediaItem.swift
//  fichier
//

import Foundation
import FichierKit

nonisolated extension MediaCacheManager {
    
    /// Resolves the canonical on-disk cached video URL for a media item.
    ///
    /// - Parameter item: The video `MediaItem`.
    /// - Returns: A file URL within `SMBVideos`.
    public func localVideoURL(for item: MediaItem) -> URL {
        localVideoURL(
            shareName: item.shareName,
            path: item.path,
            filename: item.name,
            connectionID: item.connectionID
        )
    }
    
    /// Asynchronously migrates legacy unscoped video caches to the scoped canonical path.
    public func migrateLegacyVideoIfNeeded(for item: MediaItem) async {
        await migrateLegacyVideoIfNeeded(
            shareName: item.shareName,
            path: item.path,
            filename: item.name,
            connectionID: item.connectionID
        )
    }
    
    /// Checks whether a full video file is currently cached and complete on local disk.
    public func hasCachedVideo(for item: MediaItem) -> Bool {
        hasCachedVideo(
            shareName: item.shareName,
            path: item.path,
            filename: item.name,
            connectionID: item.connectionID
        )
    }
    
    /// Resolves the on-disk file URL for a cached PDF document.
    public func localDocumentURL(for item: MediaItem) -> URL {
        localDocumentURL(
            shareName: item.shareName,
            path: item.path,
            filename: item.name,
            connectionID: item.connectionID
        )
    }
    
    /// Checks whether a complete copy of a document is cached on disk.
    public func hasCachedDocument(for item: MediaItem) -> Bool {
        hasCachedDocument(
            shareName: item.shareName,
            path: item.path,
            filename: item.name,
            connectionID: item.connectionID
        )
    }
    
    /// Asynchronously invalidates disk thumbnail and cached document copies on `MediaDiskCacheActor`.
    ///
    /// - Parameter items: The collection of `MediaItem` assets to purge from disk caches.
    public func invalidateThumbnailCache(for items: [MediaItem]) async {
        let targets = collectThumbnailURLsToRemove(for: items)
        await diskActor.removeFiles(at: targets)
    }
    
    /// Dispatches invalidation of disk thumbnail and cached document copies to `MediaDiskCacheActor`.
    ///
    /// - Parameter items: The collection of `MediaItem` assets to purge from disk caches.
    public func invalidateThumbnailCache(for items: [MediaItem]) {
        let targets = collectThumbnailURLsToRemove(for: items)
        Task(priority: .utility) { [diskActor] in
            await diskActor.removeFiles(at: targets)
        }
    }
    
    private func collectThumbnailURLsToRemove(for items: [MediaItem]) -> [URL] {
        var urlsToRemove: [URL] = []
        for item in items {
            urlsToRemove.append(contentsOf: thumbnailURLs(for: item.shareName, path: item.path, connectionID: item.connectionID))
            if item.isVideo {
                urlsToRemove.append(contentsOf: thumbnailURLs(for: item.shareName, path: "\(item.path)_vidstream_v7", connectionID: item.connectionID))
            }
            if item.isPDF {
                urlsToRemove.append(localDocumentURL(for: item))
            }
        }
        return urlsToRemove
    }
}
