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
        
        try? fm.createDirectory(at: thumbs, withIntermediateDirectories: true)
        try? fm.createDirectory(at: vids, withIntermediateDirectories: true)
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
    
    // MARK: - Cache Size & Cleanup
    
    public func calculateTotalCacheSize() -> Int64 {
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
    
    public func formattedCacheSize() -> String {
        let bytes = calculateTotalCacheSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    public func clearAllCache() {
        try? fileManager.removeItem(at: thumbnailsDirectory)
        try? fileManager.removeItem(at: videosDirectory)
        try? fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
    }
}
