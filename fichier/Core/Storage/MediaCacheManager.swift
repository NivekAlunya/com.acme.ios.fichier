//
//  MediaCacheManager.swift
//  fichier
//

import Foundation
import UIKit
import AVFoundation
import CryptoKit
import FichierKit
#if canImport(PDFKit) && !os(tvOS)
import PDFKit
#endif

/// Centralized on-disk caching engine managing thumbnail persistence, video stream buffering, and document staging.
///
/// ### Architecture & Concurrency Overview
/// - **Thread Safety & Concurrency**: Conforms to `Sendable` as an immutable coordinator with atomic filesystem operations.
///   Heavy I/O calculations (directory sweeps, eviction, size summation) execute on background detached tasks (`priority: .utility`).
/// - **Universal Master Thumbnail Dimension (420px)**: Employs a single master dimension of 420 px for all cached thumbnails.
///   Whether the user displays List, Compact Grid (120px), Medium Grid (180px), or Large Grid (280px), a single cached file
///   satisfies all views with native CoreGraphics scaling, eliminating duplicate downloads and multiple cache files per photo.
/// - **Dynamic Host Disk Budgeting**: Continuously probes available volume space via `volumeAvailableCapacityForImportantUsageKey`.
///   Under low disk conditions (< 1.5 GB free), cache ceilings automatically contract from 2 GB to 400 MB (videos)
///   and 300 MB to 100 MB (thumbnails) to prevent device storage warnings.
/// - **FIFO / Protected Eviction**: Evicts oldest accessed files first, while strictly shielding currently active URLs (`protectedURLs`).
nonisolated public final class MediaCacheManager: Sendable {
    
    /// Global shared singleton coordinator.
    public static let shared = MediaCacheManager()
    
    /// Underlying system `FileManager` reference.
    private var fileManager: FileManager { .default }
    
    /// Isolated actor serializing all background disk mutations, file migrations, and evictions.
    public let diskActor: MediaDiskCacheActor
    
    /// Local directory storing JPEG downsampled thumbnails.
    private let thumbnailsDirectory: URL
    
    /// Local directory caching downloaded video files and streaming buffers.
    private let videosDirectory: URL
    
    /// Local directory staging cached PDF documents.
    private let documentsDirectory: URL
    
    // MARK: - Initialization & Directory Bootstrap
    
    /// Initializes directories inside the user's `CachesDirectory` sandbox with `.completeUntilFirstUserAuthentication` protection.
    ///
    /// Automatically kicks off an asynchronous background maintenance pass to prune orphaned partial downloads.
    public init() {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let thumbs = caches.appendingPathComponent("SMBThumbnails", isDirectory: true)
        let vids = caches.appendingPathComponent("SMBVideos", isDirectory: true)
        let docs = caches.appendingPathComponent("SMBDocuments", isDirectory: true)
        
        self.thumbnailsDirectory = thumbs
        self.videosDirectory = vids
        self.documentsDirectory = docs
        self.diskActor = MediaDiskCacheActor.shared
        
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        try? fm.createDirectory(at: thumbs, withIntermediateDirectories: true, attributes: attributes)
        try? fm.createDirectory(at: vids, withIntermediateDirectories: true, attributes: attributes)
        try? fm.createDirectory(at: docs, withIntermediateDirectories: true, attributes: attributes)
        
        Task(priority: .background) { [self] in
            await self.performMaintenanceSweepAsync()
        }
    }
    
    // MARK: - Thumbnail Master Dimension
    
    /// The universal master pixel dimension for all on-disk cached thumbnails (420px).
    public static let standardThumbnailDimension: CGFloat = 420
    
    // MARK: - Key Hashing
    
    /// Computes a cryptographically stable SHA-256 cache key for an image thumbnail.
    ///
    /// - Parameters:
    ///   - shareName: Name of the SMB share or storage root.
    ///   - path: Canonical path to the file.
    ///   - dimension: Pixel dimension bounding box.
    ///   - connectionID: Connection identifier scoping multi-server configurations.
    /// - Returns: A 64-character lowercase hexadecimal hash string.
    public func cacheKey(for shareName: String, path: String, dimension: CGFloat = MediaCacheManager.standardThumbnailDimension, connectionID: String = "") -> String {
        let raw: String
        if connectionID.isEmpty {
            raw = "\(shareName)::\(path)_\(Int(dimension))"
        } else {
            raw = "\(connectionID)|\(shareName)::\(path)_\(Int(dimension))"
        }
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Computes a SHA-256 hash key for a video file cache location.
    ///
    /// - Parameters:
    ///   - shareName: Storage root or share name.
    ///   - path: Canonical path to the video file.
    ///   - connectionID: Scoped connection ID.
    /// - Returns: A 64-character hexadecimal hash string.
    public func videoKey(for shareName: String, path: String, connectionID: String = "") -> String {
        let raw: String
        if connectionID.isEmpty {
            raw = "\(shareName)::\(path)"
        } else {
            raw = "\(connectionID)|\(shareName)::\(path)"
        }
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Resolves primary, legacy, and fallback lookup keys for thumbnail cache reads.
    ///
    /// - Parameters:
    ///   - shareName: Storage root or share name.
    ///   - path: Canonical path to the item.
    ///   - dimension: Target display dimension.
    ///   - connectionID: Scoped connection profile ID.
    /// - Returns: A tuple of primary, unscoped fallback, and dimension-specific legacy keys.
    public func thumbnailKeys(
        for shareName: String,
        path: String,
        dimension: CGFloat = MediaCacheManager.standardThumbnailDimension,
        connectionID: String = ""
    ) -> (primary: String, fallback: String?, legacyDimensionKey: String?) {
        let standardDim = Self.standardThumbnailDimension
        let primary = cacheKey(for: shareName, path: path, dimension: standardDim, connectionID: connectionID)
        let fallback = !connectionID.isEmpty ? cacheKey(for: shareName, path: path, dimension: standardDim, connectionID: "") : nil
        let legacyDimKey = (Int(dimension) != Int(standardDim)) ? cacheKey(for: shareName, path: path, dimension: dimension, connectionID: connectionID) : nil
        return (primary, fallback, legacyDimKey)
    }
    
    // MARK: - Thumbnail Disk Cache Operations
    
    /// Synchronously retrieves a cached thumbnail image from disk.
    ///
    /// Checks primary key, and automatically migrates legacy unscoped keys if discovered.
    ///
    /// - Parameters:
    ///   - key: The primary SHA-256 key.
    ///   - fallbackKey: Legacy unscoped key.
    ///   - legacyKey: Dimension-specific key.
    /// - Returns: Decoded `UIImage`, or `nil` if not cached.
    public func getThumbnail(for key: String, fallbackKey: String? = nil, legacyKey: String? = nil) -> UIImage? {
        let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            return image
        }
        
        // Fallback to legacy key and migrate file to new scoped key atomically
        if let fallbackKey, fallbackKey != key {
            let legacyURL = thumbnailsDirectory.appendingPathComponent("\(fallbackKey).jpg")
            if fileManager.fileExists(atPath: legacyURL.path),
               let data = try? Data(contentsOf: legacyURL),
               let image = UIImage(data: data) {
                if !fileManager.fileExists(atPath: fileURL.path) {
                    try? fileManager.moveItem(at: legacyURL, to: fileURL)
                } else {
                    try? fileManager.removeItem(at: legacyURL)
                }
                return image
            }
        }
        
        // Fallback to older dimension-specific cache (e.g. 140, 200, 280) if standard 420 hasn't been generated yet
        if let legacyKey, legacyKey != key, legacyKey != fallbackKey {
            let legacyURL = thumbnailsDirectory.appendingPathComponent("\(legacyKey).jpg")
            if fileManager.fileExists(atPath: legacyURL.path),
               let data = try? Data(contentsOf: legacyURL),
               let image = UIImage(data: data) {
                return image
            }
        }
        
        return nil
    }
    
    /// Checks whether a cached thumbnail file exists on local disk for the given key.
    ///
    /// - Parameter key: The SHA-256 cache key.
    /// - Returns: `true` if the thumbnail file is present; `false` otherwise.
    public func hasThumbnail(for key: String) -> Bool {
        let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    /// Asynchronously retrieves a cached thumbnail from disk on a background worker queue.
    public func getThumbnailAsync(for key: String, fallbackKey: String? = nil, legacyKey: String? = nil) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        return self.getThumbnail(for: key, fallbackKey: fallbackKey, legacyKey: legacyKey)
    }
    
    /// Writes an image thumbnail to disk as an atomic JPEG file (82% compression quality).
    ///
    /// - Parameters:
    ///   - image: The `UIImage` to encode.
    ///   - key: The SHA-256 cache key.
    public func saveThumbnail(_ image: UIImage, for key: String) {
        let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.storage.error("Failed to write thumbnail to disk: \(error.localizedDescription)")
        }
    }
    
    /// Asynchronously saves an image thumbnail to disk isolated on `MediaDiskCacheActor`.
    public func saveThumbnailAsync(_ image: UIImage, for key: String) {
        let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        Task(priority: .utility) { [diskActor] in
            guard let data = image.jpegData(compressionQuality: 0.82) else { return }
            do {
                try await diskActor.writeData(data, to: fileURL)
            } catch {
                AppLog.storage.error("Failed to write thumbnail asynchronously: \(error.localizedDescription)")
            }
        }
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
            let (photoDiskKey, photoFallbackKey, photoLegacyKey) = thumbnailKeys(
                for: item.shareName,
                path: item.path,
                dimension: Self.standardThumbnailDimension,
                connectionID: item.connectionID
            )
            let allKeys = [photoDiskKey, photoFallbackKey, photoLegacyKey].compactMap { $0 }
            for key in allKeys {
                let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
                urlsToRemove.append(fileURL)
            }
            if item.isVideo {
                let (vidKey, vidFallback, vidLegacy) = thumbnailKeys(
                    for: item.shareName,
                    path: "\(item.path)_vidstream_v7",
                    dimension: Self.standardThumbnailDimension,
                    connectionID: item.connectionID
                )
                let vidKeys = [vidKey, vidFallback, vidLegacy].compactMap { $0 }
                for key in vidKeys {
                    let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
                    urlsToRemove.append(fileURL)
                }
            }
            if item.isPDF {
                let docURL = localDocumentURL(for: item)
                urlsToRemove.append(docURL)
            }
        }
        return urlsToRemove
    }
    
    // MARK: - Video Disk Cache
    
    /// Resolves the canonical on-disk cached video URL for a media item.
    ///
    /// Pure, side-effect-free path resolution without in-line file mutation.
    ///
    /// - Parameter item: The video `MediaItem`.
    /// - Returns: A file URL within `SMBVideos`.
    public func localVideoURL(for item: MediaItem) -> URL {
        let key = videoKey(for: item.shareName, path: item.path, connectionID: item.connectionID)
        let ext = (item.name as NSString).pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "mp4" : ext
        return videosDirectory.appendingPathComponent("\(key).\(safeExt)")
    }
    
    /// Asynchronously migrates legacy unscoped video caches to the scoped canonical path.
    public func migrateLegacyVideoIfNeeded(for item: MediaItem) async {
        guard !item.connectionID.isEmpty else { return }
        let canonicalURL = localVideoURL(for: item)
        guard !fileManager.fileExists(atPath: canonicalURL.path) else { return }
        let ext = (item.name as NSString).pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "mp4" : ext
        let legacyKey = videoKey(for: item.shareName, path: item.path, connectionID: "")
        let legacyURL = videosDirectory.appendingPathComponent("\(legacyKey).\(safeExt)")
        await diskActor.migrateFile(from: legacyURL, to: canonicalURL)
    }
    
    /// Checks whether a full video file is currently cached and complete on local disk.
    public func hasCachedVideo(for item: MediaItem) -> Bool {
        let url = localVideoURL(for: item)
        return fileManager.fileExists(atPath: url.path)
    }
    
    // MARK: - Document Cache URL Resolution
    
    /// Resolves the on-disk file URL for a cached PDF document.
    public func localDocumentURL(for item: MediaItem) -> URL {
        let key = videoKey(for: item.shareName, path: item.path, connectionID: item.connectionID)
        let ext = (item.name as NSString).pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "pdf" : ext
        return documentsDirectory.appendingPathComponent("\(key).\(safeExt)")
    }
    
    /// Checks whether a complete copy of a document is cached on disk.
    public func hasCachedDocument(for item: MediaItem) -> Bool {
        let url = localDocumentURL(for: item)
        return fileManager.fileExists(atPath: url.path)
    }
    
    // MARK: - PDF Thumbnail Generation
    
    #if canImport(PDFKit) && !os(tvOS)
    /// Renders the first page of a PDF document at the given URL into a thumbnail.
    ///
    /// - Parameters:
    ///   - url: File URL of the PDF document.
    ///   - maxDimension: Maximum thumbnail pixel size.
    /// - Returns: A rendered `UIImage` cover image, or `nil` on failure.
    public func generatePDFThumbnail(from url: URL, maxDimension: CGFloat = standardThumbnailDimension) -> UIImage? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let size = CGSize(width: maxDimension, height: maxDimension)
        return page.thumbnail(of: size, for: .mediaBox)
    }
    
    /// Renders the first page of an active parsed `PDFDocument` instance into a thumbnail.
    ///
    /// - Parameters:
    ///   - doc: The parsed `PDFDocument` instance.
    ///   - maxDimension: Maximum thumbnail pixel size.
    /// - Returns: A rendered `UIImage` cover image, or `nil` on failure.
    public func generatePDFThumbnail(from doc: PDFDocument, maxDimension: CGFloat = standardThumbnailDimension) -> UIImage? {
        guard let page = doc.page(at: 0) else { return nil }
        let size = CGSize(width: maxDimension, height: maxDimension)
        return page.thumbnail(of: size, for: .mediaBox)
    }
    
    /// Renders a PDF cover thumbnail from an in-memory byte buffer.
    ///
    /// For payloads exceeding 5 MB, stages to temporary disk storage to utilize virtual memory
    /// mapping (`mmap`) via `PDFDocument(url:)`, avoiding large dirty heap spikes during rasterization.
    /// For payloads $\le 5\text{ MB}$ (including 1 MB fast-path prefix reads), decodes purely in-memory.
    ///
    /// - Parameters:
    ///   - data: The raw PDF byte data.
    ///   - maxDimension: Maximum thumbnail pixel size.
    /// - Returns: A rendered `UIImage` cover image, or `nil` on failure.
    public func generatePDFThumbnail(from data: Data, maxDimension: CGFloat = standardThumbnailDimension) -> UIImage? {
        if data.isEmpty { return nil }
        if data.count > 5 * 1024 * 1024 {
            let tempURL = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
            do {
                try data.write(to: tempURL, options: .atomic)
                defer { try? fileManager.removeItem(at: tempURL) }
                return generatePDFThumbnail(from: tempURL, maxDimension: maxDimension)
            } catch {
                // Fall back to in-memory decoding if temporary write fails
            }
        }
        guard let doc = PDFDocument(data: data), let page = doc.page(at: 0) else { return nil }
        let size = CGSize(width: maxDimension, height: maxDimension)
        return page.thumbnail(of: size, for: .mediaBox)
    }
    #else
    public func generatePDFThumbnail(from url: URL, maxDimension: CGFloat = standardThumbnailDimension) -> UIImage? {
        nil
    }
    public func generatePDFThumbnail(from data: Data, maxDimension: CGFloat = standardThumbnailDimension) -> UIImage? {
        nil
    }
    #endif
    
    // MARK: - Video Thumbnail Timing Constants
    
    /// The default timestamp sampled for video thumbnails (15.0s) to avoid black introductory frames.
    public static let defaultVideoThumbnailTime = CMTime(seconds: 15.0, preferredTimescale: 600)
    
    /// The keyframe tolerance applied when sampling video thumbnails (2.5s) to allow instant I-frame decoding.
    public static let defaultVideoThumbnailTolerance = CMTime(seconds: 2.5, preferredTimescale: 600)
    
    /// Fallback timestamp when the video is shorter than the default thumbnail time.
    public static let fallbackVideoThumbnailTime = CMTime(seconds: 0.5, preferredTimescale: 600)
    
    // MARK: - Video Thumbnail Generation
    
    /// Generates a video thumbnail frame from a local file using `AVAssetImageGenerator`.
    ///
    /// First attempts preferred keyframe time (15s); if that fails or video is shorter, falls back to frame zero.
    ///
    /// - Parameters:
    ///   - localURL: The local video file URL.
    ///   - maxDimension: Maximum pixel bounding box.
    ///   - preferredTime: Target timestamp.
    /// - Returns: A rendered `UIImage`, or `nil` on failure.
    public func generateVideoThumbnail(
        from localURL: URL,
        maxDimension: CGFloat = standardThumbnailDimension,
        preferredTime: CMTime = defaultVideoThumbnailTime
    ) async -> UIImage? {
        if SupportedMediaTypes.isExtendedVideo(extension: localURL.pathExtension) {
            return await generateExtendedVideoThumbnail(from: localURL, maxDimension: maxDimension, preferredTime: preferredTime)
        }
        
        let asset = AVURLAsset(url: localURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = Self.defaultVideoThumbnailTolerance
        generator.requestedTimeToleranceAfter = Self.defaultVideoThumbnailTolerance
        
        // 1. Try preferred time (defaults to 15.0s):
        if let (cgImage, _) = try? await generator.image(at: preferredTime) {
            return UIImage(cgImage: cgImage)
        }
        
        // 2. Fallback to keyframe at zero (e.g. for short videos < 15s):
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
    
    /// Generates a video thumbnail frame for an extended video file (MKV, AVI, WebM, etc.).
    public func generateExtendedVideoThumbnail(
        from localURL: URL,
        maxDimension: CGFloat = standardThumbnailDimension,
        preferredTime: CMTime = defaultVideoThumbnailTime
    ) async -> UIImage? {
        let initialPosition: Float = preferredTime <= .zero ? 0.0 : 0.05
        if let thumb = await VLCVideoThumbnailActor.shared.generateThumbnail(
            from: localURL,
            maxDimension: maxDimension,
            snapshotPosition: initialPosition,
            timeoutSeconds: 4.0
        ) {
            return thumb
        }
        
        // If a non-zero timestamp was requested and failed, fall back to keyframe zero
        if preferredTime > .zero {
            if let thumb = await VLCVideoThumbnailActor.shared.generateThumbnail(
                from: localURL,
                maxDimension: maxDimension,
                snapshotPosition: 0.0,
                timeoutSeconds: 4.0
            ) {
                return thumb
            }
        }
        
        let asset = AVURLAsset(url: localURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        if let (cgImage, _) = try? await generator.image(at: preferredTime) {
            return UIImage(cgImage: cgImage)
        }
        if let (cgImage, _) = try? await generator.image(at: .zero) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
    
    // MARK: - Cache Size, Eviction & Cleanup
    
    /// Queries the filesystem to determine free available volume space in bytes.
    public func systemAvailableFreeSpace() -> Int64 {
        let cachesURL = thumbnailsDirectory
        #if !os(tvOS)
        if let values = try? cachesURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        #endif
        if let values = try? cachesURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }
        return Int64.max
    }
    
    /// Cleans up any orphaned partial download files (`.part`) older than the given duration (default 1 hour).
    public func cleanOrphanedPartFiles(olderThan seconds: TimeInterval = 3600) {
        let now = Date()
        for dir in [videosDirectory, documentsDirectory] {
            guard let enumerator = fileManager.enumerator(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "part" {
                if let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   now.timeIntervalSince(modDate) > seconds {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        }
    }
    
    /// Performs a full disk cache maintenance pass, purging partial downloads and enforcing dynamic capacity ceilings.
    ///
    /// - Parameter protecting: Set of URLs (such as currently playing videos) that must not be evicted.
    public func performMaintenanceSweep(protecting: Set<URL> = []) {
        cleanOrphanedPartFiles()
        
        let freeSpace = systemAvailableFreeSpace()
        let isLowDiskSpace = freeSpace < 1_500_000_000
        
        // Dynamically adjust disk budget according to host volume capacity
        let videoLimit: Int64 = isLowDiskSpace ? 400_000_000 : 2_000_000_000
        let docLimit: Int64 = isLowDiskSpace ? 200_000_000 : 1_000_000_000
        let thumbLimit: Int64 = isLowDiskSpace ? 100_000_000 : 300_000_000
        
        evictVideosIfNeeded(limitBytes: videoLimit, keeping: protecting)
        evictDocumentsIfNeeded(limitBytes: docLimit, keeping: protecting)
        evictThumbnailsIfNeeded(limitBytes: thumbLimit)
    }
    
    /// Asynchronously runs `performMaintenanceSweep` isolated on `MediaDiskCacheActor`.
    public func performMaintenanceSweepAsync(protecting: Set<URL> = []) async {
        let freeSpace = systemAvailableFreeSpace()
        let isLowDiskSpace = freeSpace < 1_500_000_000
        
        let videoLimit: Int64 = isLowDiskSpace ? 400_000_000 : 2_000_000_000
        let docLimit: Int64 = isLowDiskSpace ? 200_000_000 : 1_000_000_000
        let thumbLimit: Int64 = isLowDiskSpace ? 100_000_000 : 300_000_000
        
        await diskActor.cleanOrphanedPartFiles(in: [videosDirectory, documentsDirectory])
        await diskActor.evictFilesIfNeeded(in: videosDirectory, limitBytes: videoLimit, keeping: protecting)
        await diskActor.evictFilesIfNeeded(in: documentsDirectory, limitBytes: docLimit, keeping: protecting)
        await diskActor.evictFilesIfNeeded(in: thumbnailsDirectory, limitBytes: thumbLimit)
    }
    
    /// Evicts oldest cached video files (FIFO) if total video cache size exceeds `limitBytes` (default 2 GB).
    ///
    /// - Parameters:
    ///   - limitBytes: Maximum allowed aggregate size in bytes.
    ///   - protectedURLs: File URLs that must be shielded from eviction.
    public func evictVideosIfNeeded(limitBytes: Int64 = 2_000_000_000, keeping protectedURLs: Set<URL> = []) {
        guard let enumerator = fileManager.enumerator(
            at: videosDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        var videoFiles: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "part" {
                try? fileManager.removeItem(at: fileURL)
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { continue }
            let fileSize = Int64(size)
            let date = values.contentModificationDate ?? Date.distantPast
            totalSize += fileSize
            videoFiles.append((url: fileURL, size: fileSize, date: date))
        }
        
        guard totalSize > limitBytes else { return }
        
        // Sort oldest first (FIFO eviction)
        videoFiles.sort { $0.date < $1.date }
        
        for file in videoFiles {
            if totalSize <= limitBytes { break }
            if protectedURLs.contains(file.url) { continue }
            do {
                try fileManager.removeItem(at: file.url)
                totalSize -= file.size
            } catch {
                // Ignore failure to remove individual item
            }
        }
    }
    
    /// Evicts oldest cached document files (FIFO) if total document cache size exceeds `limitBytes` (default 1 GB).
    ///
    /// - Parameters:
    ///   - limitBytes: Maximum allowed aggregate size in bytes.
    ///   - protectedURLs: File URLs that must be shielded from eviction.
    public func evictDocumentsIfNeeded(limitBytes: Int64 = 1_000_000_000, keeping protectedURLs: Set<URL> = []) {
        guard let enumerator = fileManager.enumerator(
            at: documentsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        var docFiles: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "part" {
                try? fileManager.removeItem(at: fileURL)
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { continue }
            let fileSize = Int64(size)
            let date = values.contentModificationDate ?? Date.distantPast
            totalSize += fileSize
            docFiles.append((url: fileURL, size: fileSize, date: date))
        }
        
        guard totalSize > limitBytes else { return }
        
        // Sort oldest first (FIFO eviction)
        docFiles.sort { $0.date < $1.date }
        
        for file in docFiles {
            if totalSize <= limitBytes { break }
            if protectedURLs.contains(file.url) { continue }
            do {
                try fileManager.removeItem(at: file.url)
                totalSize -= file.size
            } catch {
                // Ignore failure to remove individual item
            }
        }
    }
    
    /// Evicts oldest cached thumbnails if aggregate thumbnail cache exceeds `limitBytes` (default 300 MB).
    public func evictThumbnailsIfNeeded(limitBytes: Int64 = 300_000_000) {
        guard let enumerator = fileManager.enumerator(
            at: thumbnailsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        var thumbFiles: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { continue }
            let fileSize = Int64(size)
            let date = values.contentModificationDate ?? Date.distantPast
            totalSize += fileSize
            thumbFiles.append((url: fileURL, size: fileSize, date: date))
        }
        
        guard totalSize > limitBytes else { return }
        
        thumbFiles.sort { $0.date < $1.date }
        
        for file in thumbFiles {
            if totalSize <= limitBytes { break }
            do {
                try fileManager.removeItem(at: file.url)
                totalSize -= file.size
            } catch {
                // Ignore failure to remove individual item
            }
        }
    }
    
    /// Computes aggregate cache size in bytes asynchronously isolated on `MediaDiskCacheActor`.
    public func calculateTotalCacheSize() async -> Int64 {
        await diskActor.calculateTotalSize(in: [thumbnailsDirectory, videosDirectory, documentsDirectory])
    }
    
    /// Internal synchronous summation of file sizes across thumbnail and video cache directories.
    private func calculateTotalCacheSizeInternal() -> Int64 {
        var total: Int64 = 0
        for dir in [thumbnailsDirectory, videosDirectory, documentsDirectory] {
            if let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        total += Int64(size)
                    }
                }
            }
        }
        return total
    }
    
    /// Asynchronously formats the aggregate disk cache size into a human-readable string (e.g. "124.5 MB").
    public func formattedCacheSize() async -> String {
        let bytes = await calculateTotalCacheSize()
        return formatByteCount(bytes)
    }
    
    /// Converts a byte integer into a localized string.
    private func formatByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Deletes all cached thumbnails and videos, optionally protecting designated URLs.
    public func clearAllCache(protecting: Set<URL> = []) {
        try? fileManager.removeItem(at: thumbnailsDirectory)
        try? fileManager.removeItem(at: documentsDirectory)
        
        if protecting.isEmpty {
            try? fileManager.removeItem(at: videosDirectory)
        } else {
            if let enumerator = fileManager.enumerator(at: videosDirectory, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator where !protecting.contains(fileURL) {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        }
        
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        try? fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true, attributes: attributes)
        try? fileManager.createDirectory(at: videosDirectory, withIntermediateDirectories: true, attributes: attributes)
        try? fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: attributes)
    }
    
    /// Asynchronous wrapper for `clearAllCache` executed safely on `MediaDiskCacheActor`.
    public func clearAllCacheAsync(protecting: Set<URL> = []) async {
        await diskActor.clearDirectories([thumbnailsDirectory, documentsDirectory], protectedURLs: [])
        await diskActor.clearDirectories([videosDirectory], protectedURLs: protecting)
    }
}
