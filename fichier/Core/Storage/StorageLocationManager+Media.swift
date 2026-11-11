//
//  StorageLocationManager+Media.swift
//  fichier
//

import Foundation
import UIKit
import AVFoundation
#if canImport(PDFKit) && !os(tvOS)
import PDFKit
#endif
import OSLog
import FichierKit

/// Thumbnail, streaming, document and cache-maintenance capabilities of `StorageLocationManager`.
///
/// Split out of the main file to keep navigation/connection state separate from media I/O. Thumbnail
/// work is bounded by `videoThumbnailLimiter` / `pdfThumbnailLimiter` and guarded by `expectedFolderID`
/// so results for a folder the user already left are dropped instead of cached.
extension StorageLocationManager {

    // MARK: - Download Picture / Thumbnail
    
    /// Downloads or retrieves a cached thumbnail image for a given media item.
    ///
    /// ### Multi-Tier Thumbnail Pipeline
    /// 1. **Tier 1 (RAM)**: Checks `SMBClientActor`'s in-memory `NSCache` for immediate rendering.
    /// 2. **Backend Delegation**:
    ///    - Photos Library: Delegated to `PhotoLibraryActor` (`PHCachingImageManager`).
    ///    - Local Files: Checks persistent disk cache (`MediaCacheManager`), then decodes with downsampling.
    ///    - SMB Videos: Checks disk cache, then extracts a keyframe over the network via `streamVideoThumbnail`.
    ///    - SMB Images: Checks disk cache, debounces by 40ms, and queries `SMBClientActor`.
    /// 3. **Tier 2 (Disk Storage)**: Successfully decoded images are written back to `MediaCacheManager`.
    ///
    /// - Parameters:
    ///   - item: The target media item.
    ///   - maxDimension: Maximum pixel bounding dimension for downsampling.
    /// - Returns: A decoded, downsampled `UIImage`, or `nil` if loading failed or was cancelled.
    public func downloadThumbnail(for item: MediaItem, maxDimension: CGFloat = 260) async -> UIImage? {
        if Task.isCancelled { return nil }
        
        let memoryCacheKey = "\(item.id)_thumb" as NSString
        let legacyMemoryKey = "\(item.id)_thumb_\(Int(maxDimension))" as NSString
        if let cached = worker.getCachedThumbnail(forKey: memoryCacheKey) ?? worker.getCachedThumbnail(forKey: legacyMemoryKey) {
            return cached
        }
        
        // Photos Library asset thumbnail
        if item.phAssetIdentifier != nil {
            if let thumb = await photosWorker.fetchThumbnail(for: item, maxDimension: maxDimension) {
                worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                return thumb
            }
            return nil
        }
        
        // Local or iCloud Drive file thumbnail
        if item.localURL != nil {
            // Check persistent on-disk thumbnail cache (Tier 2) to eliminate re-decoding local video/image files
            let subPath = item.isVideo ? "\(item.path)_vidstream_v7" : item.path
            let (diskKey, fallbackKey, legacyKey) = MediaCacheManager.shared.thumbnailKeys(
                for: item.shareName,
                path: subPath,
                dimension: maxDimension,
                connectionID: item.connectionID
            )
            if let diskCached = await MediaCacheManager.shared.getThumbnailAsync(for: diskKey, fallbackKey: fallbackKey, legacyKey: legacyKey) {
                worker.cacheThumbnail(diskCached, forKey: memoryCacheKey)
                return diskCached
            }
            
            if let thumb = await localWorker.fetchThumbnail(for: item, maxDimension: maxDimension) {
                worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                return thumb
            }
            return nil
        }
        
        let currentActive = activeFolderID
        // Early discard if folder already changed
        if let current = selectedFolder, item.shareName != current.shareName || !item.path.hasPrefix(current.path) {
            return nil
        }
        
        // Video thumbnail streaming & caching
        if item.isVideo {
            let (diskKey, fallbackKey, legacyKey) = MediaCacheManager.shared.thumbnailKeys(
                for: item.shareName,
                path: "\(item.path)_vidstream_v7",
                dimension: maxDimension,
                connectionID: item.connectionID
            )
            if let diskCached = await MediaCacheManager.shared.getThumbnailAsync(for: diskKey, fallbackKey: fallbackKey, legacyKey: legacyKey) {
                worker.cacheThumbnail(diskCached, forKey: memoryCacheKey)
                return diskCached
            }
            
            guard !Task.isCancelled else { return nil }
            
            // 1. If full video was already cached locally, extract frame directly from disk file (defaults to 12.0s with 0.0s fallback)
            if MediaCacheManager.shared.hasCachedVideo(for: item) {
                let localURL = MediaCacheManager.shared.localVideoURL(for: item)
                if let thumb = await MediaCacheManager.shared.generateVideoThumbnail(
                    from: localURL,
                    maxDimension: MediaCacheManager.standardThumbnailDimension
                ) {
                    worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                    MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                    return thumb
                }
            }
            
            // 2. Stream video frame on demand via AVAssetResourceLoader (reads front header + moov atom only!)
            // Debounce briefly so cells flying past during fast scroll are cancelled before hitting SMB
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return nil }
            
            if let thumb = await streamVideoThumbnail(for: item, expectedFolderID: currentActive, maxDimension: MediaCacheManager.standardThumbnailDimension) {
                worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                return thumb
            }
            
            // 3. If streaming failed or was cancelled due to scrolling, do NOT cache a placeholder
            // This allows the cell to retry fetching the actual thumbnail when visible
            return nil
        }
        
        // PDF document thumbnail streaming, fast-path prefix caching, and placeholder generation
        if item.isPDF {
            return await fetchPDFThumbnail(for: item, expectedFolderID: currentActive, maxDimension: MediaCacheManager.standardThumbnailDimension)
        }
        
        // Check persistent disk cache for SMB photos off the MainActor before queuing on SMBClientActor
        let (photoDiskKey, photoFallbackKey, photoLegacyKey) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: maxDimension,
            connectionID: item.connectionID
        )
        if let diskCached = await MediaCacheManager.shared.getThumbnailAsync(for: photoDiskKey, fallbackKey: photoFallbackKey, legacyKey: photoLegacyKey) {
            worker.cacheThumbnail(diskCached, forKey: memoryCacheKey)
            return diskCached
        }
        
        // Debounce briefly (40ms for photos) to prevent network thrashing during fast scrolls
        try? await Task.sleep(for: .milliseconds(40))
        guard !Task.isCancelled else { return nil }
        
        let thumb = await worker.fetchThumbnail(for: item, expectedFolderID: currentActive, maxDimension: maxDimension)
        if let thumb {
            worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
        }
        return thumb
    }
    
    // MARK: - Streaming Helpers
    
    /// Ensures a media item has a positive byte size populated, querying file attributes if missing.
    ///
    /// - Parameter item: The media item to validate.
    /// - Returns: The verified `MediaItem` with positive size metadata.
    public func resolveValidItem(for item: MediaItem) async -> MediaItem {
        guard item.size <= 0 else { return item }
        let realSize = await fetchFileSize(for: item)
        return realSize > 0 ? item.withSize(realSize) : item
    }

    /// Progressive video keyframe extractor over SMB using `FichierKit.SMBAVAssetResourceLoaderDelegate`.
    ///
    /// ### Algorithmic Details & Concurrency Control
    /// 1. Uses `videoThumbnailLimiter.withPermit` to cap simultaneous thumbnail extraction tasks (default max 2),
    ///    preventing socket congestion on the SMB server.
    /// 2. Configures `SMBAVAssetResourceLoaderDelegate` with a 256 KB chunk size for efficient range-request header parsing.
    /// 3. Employs `AVAssetImageGenerator` with tight tolerances targeting a standardized 15.0s timestamp,
    ///    with fallbacks to `.zero` and 0.5s if the video is very short.
    /// 4. Races the extraction against a 12-second timeout inside a structured `TaskGroup`, immediately
    ///    cancelling underlying network requests and CGImage generation upon timeout or external cancellation.
    ///
    /// - Parameters:
    ///   - item: Video media item.
    ///   - expectedFolderID: Active folder identifier to avoid completing obsolete requests.
    ///   - maxDimension: Maximum bounding dimension for the thumbnail.
    /// - Returns: An extracted keyframe image, or `nil`.
    private func streamVideoThumbnail(for item: MediaItem, expectedFolderID: String?, maxDimension: CGFloat) async -> UIImage? {
        if Task.isCancelled { return nil }
        
        return try? await videoThumbnailLimiter.withPermit {
            guard !Task.isCancelled else { return nil }
            if let expectedFolderID, await self.activeFolderID != expectedFolderID {
                return nil
            }
            let memoryCacheKey = "\(item.id)_thumb" as NSString
            let legacyMemoryKey = "\(item.id)_thumb_\(Int(maxDimension))" as NSString
            if let cached = self.worker.getCachedThumbnail(forKey: memoryCacheKey) ?? self.worker.getCachedThumbnail(forKey: legacyMemoryKey) {
                return cached
            }
            
            let validItem = await resolveValidItem(for: item)
            guard validItem.size > 0 else {
                return nil
            }
            
            guard let client = await worker.activeClient() else {
                return nil
            }
            
            return await SMBVideoThumbnailLoader.extractSMBFrame(
                client: client,
                share: validItem.shareName,
                path: validItem.smbRelativePath,
                fileName: validItem.name,
                fileSize: validItem.size,
                maxDimension: maxDimension
            )
        }
    }
    
    // MARK: - PDF Document Thumbnail Streaming & Placeholders
    
    /// Progressive PDF document thumbnail generator with fast-path prefix reading and stylized placeholder fallbacks.
    ///
    /// ### Three-Tier Thumbnailing Strategy:
    /// 1. **Cache / Local Ingestion**: Checks RAM, persistent disk thumbnails, or local document cache.
    /// 2. **Fast-Path Prefix Read**: Reads the initial 1 MB prefix over SMB. For linearized (web-optimized) PDFs,
    ///    Page 1 is rendered and cached in ~200ms without transferring the remaining document.
    /// 3. **Bounded Ingestion or Stylized Cover**:
    ///    - If the document is $\le 12 \text{ MB}$, downloads via bounded concurrency limiter (max 1 concurrent operation)
    ///      with a strict 8-second timeout to prevent socket starvation.
    ///    - If the document exceeds $12 \text{ MB}$, or if download fails/times out, immediately generates an
    ///      elegant stylized vector PDF cover card with title and file size.
    ///
    /// - Parameters:
    ///   - item: The target PDF `MediaItem`.
    ///   - expectedFolderID: Active directory token to verify folder consistency.
    ///   - maxDimension: Maximum thumbnail bounding dimension.
    /// - Returns: A rendered cover `UIImage`, or `nil` if cancelled.
    #if !os(tvOS)
    private func fetchPDFThumbnail(for item: MediaItem, expectedFolderID: String?, maxDimension: CGFloat) async -> UIImage? {
        if Task.isCancelled { return nil }
        
        let memoryCacheKey = "\(item.id)_thumb" as NSString
        let (diskKey, fallbackKey, legacyKey) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: maxDimension,
            connectionID: item.connectionID
        )
        
        // 1. Check persistent on-disk thumbnail cache
        if let diskCached = await MediaCacheManager.shared.getThumbnailAsync(for: diskKey, fallbackKey: fallbackKey, legacyKey: legacyKey) {
            worker.cacheThumbnail(diskCached, forKey: memoryCacheKey)
            return diskCached
        }
        
        // 2. Check if complete document is already cached locally (e.g. previously opened in PDFDetailView)
        if MediaCacheManager.shared.hasCachedDocument(for: item) {
            let localURL = MediaCacheManager.shared.localDocumentURL(for: item)
            if let thumb = MediaCacheManager.shared.generatePDFThumbnail(from: localURL, maxDimension: maxDimension) {
                worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                return thumb
            }
        }
        
        // 3. Debounce briefly (100ms) to cancel fast-scrolling cells before touching SMB
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return nil }
        if let expectedFolderID, self.activeFolderID != expectedFolderID {
            return nil
        }
        
        // 4. Fast-Path Prefix Read (Linearized / Web-Optimized PDFs)
        if let fastThumb = await worker.fetchPDFPrefixThumbnail(for: item, maxDimension: maxDimension) {
            worker.cacheThumbnail(fastThumb, forKey: memoryCacheKey)
            MediaCacheManager.shared.saveThumbnailAsync(fastThumb, for: diskKey)
            return fastThumb
        }
        guard !Task.isCancelled else { return nil }
        
        // 5. Size Ceiling & Concurrency Limiting:
        // Only attempt full download during grid browsing for documents <= 12 MB.
        let maxThumbnailDownloadBytes: Int64 = 12 * 1024 * 1024
        if item.size > 0 && item.size <= maxThumbnailDownloadBytes {
            let thumb = try? await pdfThumbnailLimiter.withPermit { () -> UIImage? in
                guard !Task.isCancelled else { return nil }
                if let expectedFolderID, await self.activeFolderID != expectedFolderID {
                    return nil
                }
                
                // Re-check disk cache in case a previous task finished it while waiting
                if let diskCached = await MediaCacheManager.shared.getThumbnailAsync(for: diskKey, fallbackKey: fallbackKey, legacyKey: legacyKey) {
                    return diskCached
                }
                
                do {
                    // Race download against an 8-second timeout using structured concurrency
                    return try await withThrowingTaskGroup(of: UIImage?.self) { group in
                        group.addTask {
                            let localURL = try await self.worker.fetchDocumentURL(for: item)
                            return MediaCacheManager.shared.generatePDFThumbnail(from: localURL, maxDimension: maxDimension)
                        }
                        group.addTask {
                            try await Task.sleep(for: .seconds(8))
                            return nil
                        }
                        let result = (try await group.next()).flatMap { $0 }
                        group.cancelAll()
                        return result
                    }
                } catch {
                    return nil
                }
            }
            if let thumb {
                worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                return thumb
            }
        }
        
        // 6. Documents > 12 MB or without a pre-computed thumbnail return nil.
        // MediaThumbnailView will render a zero-allocation lightweight SwiftUI vector placeholder.
        return nil
    }
    
    // MARK: - On-the-Fly Thumbnail Upgrades
    
    /// Upgrades or creates the master thumbnail for a PDF document currently opened in the reader.
    ///
    /// Extracted directly from Page 1 of the parsed in-memory `PDFDocument`, saving network I/O
    /// and disk parsing overhead. Persists the rendered thumbnail to both RAM and disk caches,
    /// and notifies active gallery cells to update immediately.
    ///
    /// - Parameters:
    ///   - item: The target document `MediaItem`.
    ///   - document: The parsed `PDFDocument` currently displayed in the reader.
    public func upgradePDFThumbnail(for item: MediaItem, from document: PDFDocument) async {
        let maxDimension = MediaCacheManager.standardThumbnailDimension
        let (diskKey, _, _) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: maxDimension,
            connectionID: item.connectionID
        )
        let memoryCacheKey = "\(item.id)_thumb" as NSString
        
        // Render first page directly from in-memory document
        guard let thumb = MediaCacheManager.shared.generatePDFThumbnail(from: document, maxDimension: maxDimension) else {
            return
        }
        
        // Persist to disk and RAM
        MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
        worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
        
        // Trigger SwiftUI observation update for this item
        thumbnailVersions[item.id, default: 0] += 1
    }
    #else
    private func fetchPDFThumbnail(for item: MediaItem, expectedFolderID: String?, maxDimension: CGFloat) async -> UIImage? {
        nil
    }
    #endif
    
    /// Downloads the full-resolution image for a media item from the active backend.
    ///
    /// - Parameter item: The media item to download.
    /// - Returns: The full-resolution `UIImage`, or `nil` if cancelled or failed.
    nonisolated public func downloadImage(for item: MediaItem) async -> UIImage? {
        if Task.isCancelled || item.isVideo { return nil }
        if item.phAssetIdentifier != nil {
            return await photosWorker.fetchImage(for: item)
        }
        if item.localURL != nil {
            return await localWorker.fetchImage(for: item)
        }
        return await worker.fetchFullImage(for: item)
    }
    
    /// Queries the byte size of a media item from its respective storage backend.
    ///
    /// - Parameter item: The media item to inspect.
    /// - Returns: Size in bytes, or `0` if undetermined.
    nonisolated public func fetchFileSize(for item: MediaItem) async -> Int64 {
        if item.phAssetIdentifier != nil {
            return await photosWorker.fetchFileSize(for: item)
        }
        if item.localURL != nil {
            return await localWorker.fetchFileSize(for: item)
        }
        return await worker.fetchFileSize(for: item)
    }
    
    /// Fetches parsed EXIF and camera metadata for an image without decoding pixel buffers.
    ///
    /// - Parameter item: The media item to inspect.
    /// - Returns: Parsed `PictureEXIFData`, or `nil` if unavailable.
    nonisolated public func fetchMetadata(for item: MediaItem) async -> PictureEXIFData? {
        if Task.isCancelled { return nil }
        if item.phAssetIdentifier != nil {
            return await photosWorker.fetchMetadata(for: item)
        }
        if item.localURL != nil {
            return await localWorker.fetchMetadata(for: item)
        }
        return await worker.fetchMetadata(for: item)
    }
    
    // MARK: - Video Support & Disk Cache (Tier 3)
    
    /// Fetches a specific byte range of a media file over SMB.
    ///
    /// - Parameters:
    ///   - item: The media item being streamed.
    ///   - offset: Starting byte position.
    ///   - length: Requested number of bytes.
    /// - Returns: The retrieved byte chunk.
    nonisolated public func fetchMediaRange(for item: MediaItem, offset: Int64, length: Int) async throws -> Data {
        try await worker.fetchMediaRange(for: item, offset: offset, length: length)
    }
    
    /// Resolves or downloads the playable local or sandbox file URL for a video asset.
    ///
    /// - Parameters:
    ///   - item: Target video media item.
    ///   - progress: Optional progress reporting callback (`Sendable`).
    /// - Returns: Local file `URL` ready for AVPlayer playback.
    public func fetchVideoURL(for item: MediaItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        if item.phAssetIdentifier != nil {
            return try await photosWorker.fetchVideoURL(for: item)
        }
        if let localURL = item.localURL {
            return localURL
        }
        return try await worker.fetchVideoURL(for: item, progress: progress)
    }
    
    /// Resolves or downloads the local file URL for a PDF document asset.
    ///
    /// - Parameters:
    ///   - item: Target document media item.
    ///   - progress: Optional progress reporting callback (`Sendable`).
    /// - Returns: Local file `URL` ready for PDFKit rendering.
    public func fetchDocumentURL(for item: MediaItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        if let localURL = item.localURL {
            return localURL
        }
        return try await worker.fetchDocumentURL(for: item, progress: progress)
    }
    
    /// Queries `MediaCacheManager` and updates `mediaCacheSize` on the `@MainActor`.
    public func refreshMediaCacheSize() async {
        mediaCacheSize = await MediaCacheManager.shared.formattedCacheSize()
    }
    
    /// Purges all cached thumbnails and downloads from both RAM and disk caches.
    public func clearMediaCache() {
        Task {
            await MediaCacheManager.shared.clearAllCacheAsync()
            await worker.clearMemoryCache()
            await refreshMediaCacheSize()
        }
    }
    
    /// Clears both memory and persistent disk thumbnail caches for all items in the currently loaded folder.
    public func invalidateCurrentFolderThumbnails() async {
        let items = pictures
        guard !items.isEmpty else { return }
        
        await MediaCacheManager.shared.invalidateThumbnailCache(for: items)
        
        let ids = items.map(\.id)
        await worker.removeThumbnailsFromMemory(for: ids)
        for id in ids {
            thumbnailVersions[id, default: 0] += 1
        }
        
        await refreshMediaCacheSize()
    }
}
