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
    
    public func saveVideoData(_ data: Data, for item: SMBItem) throws -> URL {
        let destination = localVideoURL(for: item)
        try data.write(to: destination, options: .atomic)
        return destination
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
    
    public func generateVideoPlaceholder(for item: SMBItem, maxDimension: CGFloat) -> UIImage {
        let size = CGSize(width: maxDimension, height: maxDimension)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Slate / dark background gradient
            let colors = [
                UIColor(red: 0.14, green: 0.16, blue: 0.22, alpha: 1.0).cgColor,
                UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0).cgColor
            ]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 1.0]) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            
            // Draw centered play glyph
            let config = UIImage.SymbolConfiguration(pointSize: maxDimension * 0.28, weight: .semibold)
            if let symbol = UIImage(systemName: "play.circle.fill", withConfiguration: config)?.withTintColor(.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal) {
                let symSize = symbol.size
                let symRect = CGRect(
                    x: (size.width - symSize.width) / 2,
                    y: (size.height - symSize.height) / 2 - 6,
                    width: symSize.width,
                    height: symSize.height
                )
                symbol.draw(in: symRect)
            }
            
            // Draw format extension label (e.g. "MP4" or "MOV")
            let ext = (item.name as NSString).pathExtension.uppercased()
            let font = UIFont.systemFont(ofSize: max(10, maxDimension * 0.075), weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ]
            let str = NSAttributedString(string: ext, attributes: attrs)
            let strSize = str.size()
            let strRect = CGRect(
                x: (size.width - strSize.width) / 2,
                y: size.height - strSize.height - (maxDimension * 0.12),
                width: strSize.width,
                height: strSize.height
            )
            str.draw(in: strRect)
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
