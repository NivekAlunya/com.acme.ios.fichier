//
//  SMBClientActor+MediaLoading.swift
//  fichier
//

import Foundation
import UIKit
import Wappn
import FichierKit

extension SMBClientActor {
    // MARK: - Thumbnail Retrieval & Downsampling

    /// Fetches and downsamples a media thumbnail using a 2-tier caching hierarchy (RAM + Disk).
    ///
    /// - Parameters:
    ///   - item: The target `MediaItem`.
    ///   - expectedFolderID: The folder ID at the time the request was dispatched.
    ///   - maxDimension: Maximum pixel dimension for the rendered thumbnail.
    /// - Returns: A downsampled `UIImage`, or `nil` on failure or cancellation.
    func fetchThumbnail(
        for item: MediaItem,
        expectedFolderID: String? = nil,
        maxDimension: CGFloat = MediaCacheManager.standardThumbnailDimension
    ) async -> UIImage? {
        if Task.isCancelled || item.isVideo { return nil }
        if let expected = expectedFolderID, let active = activeFolderID, expected != active {
            return nil
        }

        // 1. In-Memory RAM Cache check (Tier 1) - unified across all view modes
        let memoryCacheKey = "\(item.id)_thumb" as NSString
        let legacyMemoryKey = "\(item.id)_thumb_\(Int(maxDimension))" as NSString
        if let cached = thumbnailCache.object(forKey: memoryCacheKey) ?? thumbnailCache.object(forKey: legacyMemoryKey) {
            return cached
        }

        // 2. Persistent On-Disk Cache check (Tier 2 - Bypasses Wi-Fi / SMB completely!)
        let (diskKey, fallbackKey, legacyKey) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: maxDimension,
            connectionID: item.connectionID
        )
        if let diskCached = MediaCacheManager.shared.getThumbnail(for: diskKey, fallbackKey: fallbackKey, legacyKey: legacyKey) {
            thumbnailCache.setObject(diskCached, forKey: memoryCacheKey)
            return diskCached
        }

        if Task.isCancelled { return nil }
        if let expected = expectedFolderID, let active = activeFolderID, expected != active {
            return nil
        }

        guard let client else { return nil }

        do {
            // Photo Thumbnail Handling via FichierKit SMBClientProtocol
            let data = try await client.readFileData(
                share: item.shareName,
                path: item.smbRelativePath,
                maxBytes: Self.maxThumbnailDownloadBytes
            )
            if Task.isCancelled { return nil }
            if let expected = expectedFolderID, let active = activeFolderID, expected != active {
                return nil
            }

            // Extract and cache metadata immediately while image bytes are in memory
            if metadataCache.object(forKey: item.id as NSString) == nil {
                let meta = ImageMetadataExtractor.extract(from: data, fileName: item.name, fileSize: item.formattedSize)
                metadataCache.setObject(PictureEXIFBox(meta), forKey: item.id as NSString)
                if let dims = meta.dimensions {
                    Task { @MainActor in
                        MediaDetailStore.shared.registerDetail(dims, for: item.id)
                    }
                }
            }

            // Offload CPU-bound image downsampling and disk caching off the actor lock
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let decoded = SMBImageLoader.decodeDownsampledImage(from: data, maxPixelSize: MediaCacheManager.standardThumbnailDimension) ?? AnimatedImageDecoder.decode(from: data) else {
                    return nil
                }
                MediaCacheManager.shared.saveThumbnail(decoded, for: diskKey)
                return decoded
            }.value

            if let image {
                thumbnailCache.setObject(image, forKey: memoryCacheKey)
            }
            return image
        } catch {
            if !Task.isCancelled {
                loge("Failed to load thumbnail at \(item.shareName)/\(item.path): \(error.localizedDescription)")
            }
            return nil
        }
    }

    /// Attempts fast-path prefix thumbnail generation for linearized / web-optimized PDFs.
    ///
    /// Reads only the initial 1 MB prefix of the document. If linearized, Page 1 can be parsed
    /// and rendered immediately without downloading the full document.
    func fetchPDFPrefixThumbnail(for item: MediaItem, maxDimension: CGFloat = MediaCacheManager.standardThumbnailDimension) async -> UIImage? {
        let (diskKey, fallbackKey, legacyKey) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: maxDimension,
            connectionID: item.connectionID
        )
        let memoryCacheKey = "\(item.id)_thumb" as NSString

        // 1. In-memory RAM Cache check
        if let memoryCached = thumbnailCache.object(forKey: memoryCacheKey) {
            return memoryCached
        }

        // 2. Persistent On-Disk Cache check
        if let diskCached = MediaCacheManager.shared.getThumbnail(for: diskKey, fallbackKey: fallbackKey, legacyKey: legacyKey) {
            thumbnailCache.setObject(diskCached, forKey: memoryCacheKey)
            return diskCached
        }

        guard let client, !Task.isCancelled else { return nil }

        // Resolve actual file size to avoid out-of-bounds prefix requests on small files
        var fileSize = item.size
        if fileSize <= 0 {
            fileSize = await fetchFileSize(for: item)
        }
        guard fileSize > 0 else { return nil }

        let prefixLength: Int64 = min(fileSize, 1_048_576)
        do {
            let prefixData = try await client.readFileData(share: item.shareName, path: item.smbRelativePath, maxBytes: prefixLength)
            if !prefixData.isEmpty,
               let thumb = MediaCacheManager.shared.generatePDFThumbnail(from: prefixData, maxDimension: maxDimension) {
                thumbnailCache.setObject(thumb, forKey: memoryCacheKey)
                MediaCacheManager.shared.saveThumbnail(thumb, for: diskKey)
                return thumb
            }
        } catch {
            if !Task.isCancelled {
                logw("Fast-path prefix read failed at \(item.shareName)/\(item.path): \(error.localizedDescription)")
            }
        }
        return nil
    }

    // MARK: - Video & Document Local Caching

    /// Stages a remote SMB download into a temporary `.part` file, promoting it to `localURL` only upon completion.
    private func downloadStaged(
        share: String,
        path: String,
        to localURL: URL,
        progress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws {
        guard let client else {
            throw URLError(.notConnectedToInternet)
        }
        let partURL = localURL.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partURL)

        do {
            try await client.downloadFile(share: share, path: path, to: partURL) { bytes, total in
                if Task.isCancelled { return false }
                progress?(bytes, total)
                return true
            }

            if Task.isCancelled {
                try? FileManager.default.removeItem(at: partURL)
                throw CancellationError()
            }

            if FileManager.default.fileExists(atPath: localURL.path) {
                do {
                    _ = try FileManager.default.replaceItemAt(localURL, withItemAt: partURL, backupItemName: nil, options: [])
                } catch {
                    try? FileManager.default.removeItem(at: localURL)
                    try FileManager.default.moveItem(at: partURL, to: localURL)
                }
            } else {
                try FileManager.default.moveItem(at: partURL, to: localURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: partURL)
            throw error
        }
    }

    /// Streams a video file from SMB directly to disk cache via `.part` staging.
    func fetchVideoURL(for item: MediaItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        let localURL = MediaCacheManager.shared.localVideoURL(for: item)
        if MediaCacheManager.shared.hasCachedVideo(for: item) {
            return localURL
        }

        try await downloadStaged(share: item.shareName, path: item.smbRelativePath, to: localURL, progress: progress)

        // Evict older videos if cache exceeds limit, protecting the newly downloaded one
        MediaCacheManager.shared.evictVideosIfNeeded(keeping: [localURL])

        // Upgrade thumbnail cache with real video frame now that it is downloaded
        let (diskKey, _, _) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: MediaCacheManager.thumbnailCacheSubPath(for: item.path, isVideo: true),
            dimension: MediaCacheManager.standardThumbnailDimension,
            connectionID: item.connectionID
        )
        if let thumb = await MediaCacheManager.shared.generateVideoThumbnail(
            from: localURL,
            maxDimension: MediaCacheManager.standardThumbnailDimension,
            preferredTime: MediaCacheManager.defaultVideoThumbnailTime
        ) {
            let memoryCacheKey = "\(item.id)_thumb" as NSString
            thumbnailCache.setObject(thumb, forKey: memoryCacheKey)
            MediaCacheManager.shared.saveThumbnail(thumb, for: diskKey)
        }

        return localURL
    }

    /// Downloads an entire document (e.g. PDF) to persistent local disk cache via `.part` staging.
    func fetchDocumentURL(for item: MediaItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        let localURL = MediaCacheManager.shared.localDocumentURL(for: item)
        if MediaCacheManager.shared.hasCachedDocument(for: item) {
            return localURL
        }

        try await downloadStaged(share: item.shareName, path: item.smbRelativePath, to: localURL, progress: progress)

        // Evict older documents if cache exceeds limit, protecting the newly downloaded one
        MediaCacheManager.shared.evictDocumentsIfNeeded(keeping: [localURL])

        // Upgrade thumbnail cache with rendered PDF cover page
        let (diskKey, _, _) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: MediaCacheManager.standardThumbnailDimension,
            connectionID: item.connectionID
        )
        if let thumb = MediaCacheManager.shared.generatePDFThumbnail(from: localURL, maxDimension: MediaCacheManager.standardThumbnailDimension) {
            let memoryCacheKey = "\(item.id)_thumb" as NSString
            thumbnailCache.setObject(thumb, forKey: memoryCacheKey)
            MediaCacheManager.shared.saveThumbnail(thumb, for: diskKey)
        }

        return localURL
    }

    /// Downloads any media item directly to local disk cache with progress reporting.
    func downloadItemToFile(for item: MediaItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        if item.isVideo {
            return try await fetchVideoURL(for: item, progress: progress)
        }
        if item.isDocument {
            return try await fetchDocumentURL(for: item, progress: progress)
        }
        let localURL = MediaCacheManager.shared.localDocumentURL(for: item)
        if FileManager.default.fileExists(atPath: localURL.path) {
            progress?(item.size, item.size)
            return localURL
        }
        try await downloadStaged(share: item.shareName, path: item.smbRelativePath, to: localURL, progress: progress)
        return localURL
    }

    /// Flushes all in-memory caches to immediately release RAM upon system low-memory warnings.
    func clearMemoryCache() {
        thumbnailCache.removeAllObjects()
        fullImageCache.removeAllObjects()
        metadataCache.removeAllObjects()
    }

    /// Removes memory cached thumbnails matching the specified item identifiers.
    ///
    /// - Parameter itemIDs: The array of `MediaItem.id` strings to evict from RAM.
    func removeThumbnailsFromMemory(for itemIDs: [String]) {
        for id in itemIDs {
            thumbnailCache.removeObject(forKey: "\(id)_thumb" as NSString)
        }
    }

    // MARK: - Streaming Media Byte Range Requests

    /// Reads a discrete byte range over SMB via `FichierKit.SMBClientProtocol`.
    func fetchMediaRange(for item: MediaItem, offset: Int64, length: Int) async throws -> Data {
        try Task.checkCancellation()
        guard let client else {
            throw URLError(.notConnectedToInternet)
        }
        return try await client.readMediaRange(
            share: item.shareName,
            path: item.smbRelativePath,
            offset: offset,
            length: length
        )
    }

    /// Queries the file size attribute from the server if not populated during directory traversal.
    func fetchFileSize(for item: MediaItem) async -> Int64 {
        if item.size > 0 { return item.size }
        if Task.isCancelled { return 0 }
        guard let client else { return 0 }
        do {
            return try await client.fileSize(share: item.shareName, path: item.smbRelativePath)
        } catch {
            return 0
        }
    }

    // MARK: - Full Image & EXIF Metadata Fetching

    /// Downloads the full-resolution picture, decoding and caching it in `fullImageCache` for slideshow presentation.
    func fetchFullImage(for item: MediaItem) async -> UIImage? {
        if Task.isCancelled || item.isVideo { return nil }

        let cacheKey = "\(item.id)_full" as NSString
        if let cached = fullImageCache.object(forKey: cacheKey) {
            return cached
        }

        guard let client, !Task.isCancelled else { return nil }

        do {
            let data = try await client.readFileData(share: item.shareName, path: item.smbRelativePath, maxBytes: nil)
            if Task.isCancelled { return nil }

            // Ensure metadata is cached from downloaded full image bytes
            if metadataCache.object(forKey: item.id as NSString) == nil {
                let meta = ImageMetadataExtractor.extract(from: data, fileName: item.name, fileSize: item.formattedSize)
                metadataCache.setObject(PictureEXIFBox(meta), forKey: item.id as NSString)
            }

            let decodedImage = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                AnimatedImageDecoder.decode(from: data)
            }.value
            guard let image = decodedImage else { return nil }

            let widthInPixels = image.size.width * image.scale
            let heightInPixels = image.size.height * image.scale
            let pixelCost = Int(widthInPixels * heightInPixels * 4.0)

            fullImageCache.setObject(image, forKey: cacheKey, cost: max(data.count, pixelCost))
            return image
        } catch {
            if !Task.isCancelled {
                loge("Failed to load full image at \(item.shareName)/\(item.path): \(error.localizedDescription)")
            }
            return nil
        }
    }

    /// Extracts EXIF and camera metadata for an item using a 64 KB header range read before full-file fallback.
    func fetchMetadata(for item: MediaItem) async -> PictureEXIFData? {
        if Task.isCancelled { return nil }
        if item.isVideo {
            let dateStr = item.modifiedDate?.formatted(date: .abbreviated, time: .shortened)
            return PictureEXIFData(
                fileName: item.name,
                fileSize: item.formattedSize,
                dimensions: nil,
                megapixels: nil,
                cameraModel: nil,
                lensModel: nil,
                focalLength: nil,
                aperture: nil,
                shutterSpeed: nil,
                iso: nil,
                dateTaken: dateStr,
                fileFormat: (item.name as NSString).pathExtension.uppercased()
            )
        }

        let cacheKey = item.id as NSString
        if let cached = metadataCache.object(forKey: cacheKey)?.value {
            return cached
        }

        guard let client else { return nil }

        do {
            // Fast single-packet fetch: Read first 64 KB prefix to extract EXIF header
            let rangeData = try? await client.readFileData(share: item.shareName, path: item.smbRelativePath, maxBytes: 65536)
            if let rangeData, !rangeData.isEmpty {
                let meta = ImageMetadataExtractor.extract(from: rangeData, fileName: item.name, fileSize: item.formattedSize)
                if meta.dimensions != nil || meta.cameraModel != nil || meta.dateTaken != nil {
                    metadataCache.setObject(PictureEXIFBox(meta), forKey: cacheKey)
                    return meta
                }
            }

            if Task.isCancelled { return nil }
            let data = try await client.readFileData(share: item.shareName, path: item.smbRelativePath, maxBytes: nil)
            if Task.isCancelled { return nil }
            let meta = ImageMetadataExtractor.extract(from: data, fileName: item.name, fileSize: item.formattedSize)
            metadataCache.setObject(PictureEXIFBox(meta), forKey: cacheKey)
            return meta
        } catch {
            return nil
        }
    }
}
