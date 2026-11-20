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

    /// Asynchronously migrates thumbnail, video, and document disk caches when an item is renamed.
    ///
    /// - Parameters:
    ///   - source: Original `MediaItem` before rename.
    ///   - destination: Mutated `MediaItem` after rename.
    public func migrateThumbnailCache(from source: MediaItem, to destination: MediaItem) async {
        let sourceSubPath = source.isVideo ? "\(source.path)_vidstream_v7" : source.path
        let destSubPath = destination.isVideo ? "\(destination.path)_vidstream_v7" : destination.path

        let sourceKey = cacheKey(
            for: source.shareName,
            path: sourceSubPath,
            dimension: Self.standardThumbnailDimension,
            connectionID: source.connectionID
        )
        let destKey = cacheKey(
            for: destination.shareName,
            path: destSubPath,
            dimension: Self.standardThumbnailDimension,
            connectionID: destination.connectionID
        )

        let sourceURL = thumbnailsDirectory.appendingPathComponent("\(sourceKey).jpg")
        let destURL = thumbnailsDirectory.appendingPathComponent("\(destKey).jpg")

        await diskActor.migrateFile(from: sourceURL, to: destURL)

        if source.isPDF {
            let sourceDocURL = localDocumentURL(for: source)
            let destDocURL = localDocumentURL(for: destination)
            await diskActor.migrateFile(from: sourceDocURL, to: destDocURL)
        }

        if source.isVideo {
            let sourceVideoURL = localVideoURL(for: source)
            let destVideoURL = localVideoURL(for: destination)
            await diskActor.migrateFile(from: sourceVideoURL, to: destVideoURL)
        }
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
        items.flatMap { item -> [URL] in
            var urls = thumbnailURLs(for: item.shareName, path: item.path, connectionID: item.connectionID)
            if item.isVideo {
                urls.append(contentsOf: thumbnailURLs(for: item.shareName, path: "\(item.path)_vidstream_v7", connectionID: item.connectionID))
            }
            if item.isPDF {
                urls.append(localDocumentURL(for: item))
            }
            return urls
        }
    }
}
