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
    }
    
    // MARK: - Key Hashing
    
    public func cacheKey(for shareName: String, path: String, dimension: CGFloat) -> String {
        let raw = "\(shareName)::\(path)_\(Int(dimension))"
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    public func videoKey(for shareName: String, path: String) -> String {
        let raw = "\(shareName)::\(path)"
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Thumbnail Disk Cache
    
    public func getThumbnail(for key: String) -> UIImage? {
        let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
    
    public func saveThumbnail(_ image: UIImage, for key: String) {
        let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    
    // MARK: - Video Disk Cache
    
    public func localVideoURL(for item: SMBItem) -> URL {
        let key = videoKey(for: item.shareName, path: item.path)
        let ext = (item.name as NSString).pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "mp4" : ext
        return videosDirectory.appendingPathComponent("\(key).\(safeExt)")
    }
    
    public func hasCachedVideo(for item: SMBItem) -> Bool {
        let url = localVideoURL(for: item)
        return fileManager.fileExists(atPath: url.path)
    }
    
    // MARK: - Video Thumbnail Generation
    
    public func generateVideoThumbnail(
        from localURL: URL,
        maxDimension: CGFloat,
        preferredTime: CMTime = CMTime(seconds: 5.0, preferredTimescale: 600)
    ) async -> UIImage? {
        let asset = AVURLAsset(url: localURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension * 2, height: maxDimension * 2)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 2.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 2.5, preferredTimescale: 600)
        
        // 1. Try preferred time (defaults to 5.0s):
        if let (cgImage, _) = try? await generator.image(at: preferredTime) {
            return UIImage(cgImage: cgImage)
        }
        
        // 2. Fallback to keyframe at zero (e.g. for short videos < 5s):
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
    
    /// Computes total cache size on a background thread to prevent UI hitches
    public func calculateTotalCacheSize() async -> Int64 {
        await Task.detached(priority: .utility) { [self] in
            self.calculateTotalCacheSizeSync()
        }.value
    }
    
    public func calculateTotalCacheSizeSync() -> Int64 {
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
    
    public func formattedCacheSize() -> String {
        let bytes = calculateTotalCacheSizeSync()
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
}
