//
//  MediaCacheManager.swift
//  fichier
//

import Foundation
import UIKit
import AVFoundation
import CryptoKit

nonisolated public final class MediaCacheManager: Sendable {
    public static let shared = MediaCacheManager()
    
    private var fileManager: FileManager { .default }
    private let thumbnailsDirectory: URL
    private let videosDirectory: URL
    
    public init() {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let thumbs = caches.appendingPathComponent("SMBThumbnails", isDirectory: true)
        let vids = caches.appendingPathComponent("SMBVideos", isDirectory: true)
        
        self.thumbnailsDirectory = thumbs
        self.videosDirectory = vids
        
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        try? fm.createDirectory(at: thumbs, withIntermediateDirectories: true, attributes: attributes)
        try? fm.createDirectory(at: vids, withIntermediateDirectories: true, attributes: attributes)
        
        Task.detached(priority: .background) { [self] in
            self.performMaintenanceSweep()
        }
    }
    
    // MARK: - Thumbnail Master Dimension
    
    /// The universal master dimension (in pixels) for all thumbnails cached on disk.
    /// Eliminates redundant SMB fetches and re-encodings across List, Compact, Medium, and Large view modes.
    public static let standardThumbnailDimension: CGFloat = 420
    
    // MARK: - Key Hashing
    
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
    
    // MARK: - Thumbnail Disk Cache
    
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
    
    public func getThumbnailAsync(for key: String, fallbackKey: String? = nil, legacyKey: String? = nil) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { [self] in
            guard !Task.isCancelled else { return nil }
            return self.getThumbnail(for: key, fallbackKey: fallbackKey, legacyKey: legacyKey)
        }.value
    }
    
    public func saveThumbnail(_ image: UIImage, for key: String) {
        let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    
    public func saveThumbnailAsync(_ image: UIImage, for key: String) {
        Task.detached(priority: .utility) { [self] in
            self.saveThumbnail(image, for: key)
        }
    }
    
    // MARK: - Video Disk Cache
    
    public func localVideoURL(for item: MediaItem) -> URL {
        let key = videoKey(for: item.shareName, path: item.path, connectionID: item.connectionID)
        let ext = (item.name as NSString).pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "mp4" : ext
        let url = videosDirectory.appendingPathComponent("\(key).\(safeExt)")
        
        // Migrate legacy video cache if present
        if !item.connectionID.isEmpty && !fileManager.fileExists(atPath: url.path) {
            let legacyKey = videoKey(for: item.shareName, path: item.path, connectionID: "")
            let legacyURL = videosDirectory.appendingPathComponent("\(legacyKey).\(safeExt)")
            if fileManager.fileExists(atPath: legacyURL.path) {
                try? fileManager.moveItem(at: legacyURL, to: url)
            }
        }
        
        return url
    }
    
    public func hasCachedVideo(for item: MediaItem) -> Bool {
        let url = localVideoURL(for: item)
        return fileManager.fileExists(atPath: url.path)
    }
    
    // MARK: - Video Thumbnail Timing Constants
    
    /// The default timestamp sampled for video thumbnails to capture a representative scene beyond introductory title cards/black frames.
    public static let defaultVideoThumbnailTime = CMTime(seconds: 12.0, preferredTimescale: 600)
    
    /// The tolerance applied when sampling video thumbnail keyframes, allowing fast keyframe selection without decoding all preceding frames.
    public static let defaultVideoThumbnailTolerance = CMTime(seconds: 2.5, preferredTimescale: 600)
    
    /// Fallback timestamp when the video is shorter than the default thumbnail time.
    public static let fallbackVideoThumbnailTime = CMTime(seconds: 0.5, preferredTimescale: 600)
    
    // MARK: - Video Thumbnail Generation
    
    public func generateVideoThumbnail(
        from localURL: URL,
        maxDimension: CGFloat = standardThumbnailDimension,
        preferredTime: CMTime = defaultVideoThumbnailTime
    ) async -> UIImage? {
        let asset = AVURLAsset(url: localURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = Self.defaultVideoThumbnailTolerance
        generator.requestedTimeToleranceAfter = Self.defaultVideoThumbnailTolerance
        
        // 1. Try preferred time (defaults to 12.0s):
        if let (cgImage, _) = try? await generator.image(at: preferredTime) {
            return UIImage(cgImage: cgImage)
        }
        
        // 2. Fallback to keyframe at zero (e.g. for short videos < 10s):
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
    
    // MARK: - Cache Size, Eviction & Cleanup
    
    /// Returns the approximate available free volume space in bytes.
    public func systemAvailableFreeSpace() -> Int64 {
        let cachesURL = thumbnailsDirectory
        if let values = try? cachesURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        if let values = try? cachesURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }
        return Int64.max
    }
    
    /// Cleans up any leftover temporary partial download files (.part) that are older than the specified age (default 1 hour).
    public func cleanOrphanedPartFiles(olderThan seconds: TimeInterval = 3600) {
        guard let enumerator = fileManager.enumerator(
            at: videosDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        let now = Date()
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "part" {
                if let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   now.timeIntervalSince(modDate) > seconds {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        }
    }
    
    /// Performs a comprehensive disk cache hygiene pass:
    /// 1. Prunes orphaned partial `.part` downloads left over from interrupted saves or app termination.
    /// 2. Dynamically assesses host volume free space; under low disk space (< 1.5 GB), cuts cache limits
    ///    to 400 MB (videos) and 100 MB (thumbnails) so the app never triggers system low-space warnings.
    /// 3. Evicts oldest thumbnails and video files (FIFO) while respecting `protectedURLs`.
    public func performMaintenanceSweep(protecting: Set<URL> = []) {
        cleanOrphanedPartFiles()
        
        let freeSpace = systemAvailableFreeSpace()
        let isLowDiskSpace = freeSpace < 1_500_000_000
        
        // Dynamically adjust disk budget according to host volume capacity
        let videoLimit: Int64 = isLowDiskSpace ? 400_000_000 : 2_000_000_000
        let thumbLimit: Int64 = isLowDiskSpace ? 100_000_000 : 300_000_000
        
        evictVideosIfNeeded(limitBytes: videoLimit, keeping: protecting)
        evictThumbnailsIfNeeded(limitBytes: thumbLimit)
    }
    
    /// Async wrapper for `performMaintenanceSweep` dispatched on background utility QoS.
    public func performMaintenanceSweepAsync(protecting: Set<URL> = []) async {
        await Task.detached(priority: .utility) { [self] in
            self.performMaintenanceSweep(protecting: protecting)
        }.value
    }
    
    /// Evicts oldest cached videos if total video cache size exceeds limitBytes (defaults to 2 GB),
    /// skipping any files specified in `protectedURLs` (such as the currently playing video).
    public func evictVideosIfNeeded(limitBytes: Int64 = 2_000_000_000, keeping protectedURLs: Set<URL> = []) {
        guard let enumerator = fileManager.enumerator(
            at: videosDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        var videoFiles: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            // Clean up any stale partial downloads (.part)
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
    
    /// Evicts oldest cached thumbnails if total thumbnail cache size exceeds limitBytes (defaults to 300 MB).
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
    
    /// Computes total cache size on a background thread to prevent UI hitches
    public func calculateTotalCacheSize() async -> Int64 {
        await Task.detached(priority: .utility) { [self] in
            self.calculateTotalCacheSizeInternal()
        }.value
    }
    
    private func calculateTotalCacheSizeInternal() -> Int64 {
        var total: Int64 = 0
        for dir in [thumbnailsDirectory, videosDirectory] {
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
    
    public func formattedCacheSize() async -> String {
        let bytes = await calculateTotalCacheSize()
        return formatByteCount(bytes)
    }
    
    private func formatByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    public func clearAllCache(protecting: Set<URL> = []) {
        try? fileManager.removeItem(at: thumbnailsDirectory)
        
        if protecting.isEmpty {
            try? fileManager.removeItem(at: videosDirectory)
        } else {
            // Delete everything except protected files
            if let enumerator = fileManager.enumerator(at: videosDirectory, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if !protecting.contains(fileURL) {
                        try? fileManager.removeItem(at: fileURL)
                    }
                }
            }
        }
        
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        try? fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true, attributes: attributes)
        try? fileManager.createDirectory(at: videosDirectory, withIntermediateDirectories: true, attributes: attributes)
    }
    
    public func clearAllCacheAsync(protecting: Set<URL> = []) async {
        await Task.detached(priority: .utility) { [self] in
            self.clearAllCache(protecting: protecting)
        }.value
    }
}
