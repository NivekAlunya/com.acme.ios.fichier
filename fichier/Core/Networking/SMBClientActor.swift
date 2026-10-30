//
//  SMBClientActor.swift
//  fichier
//

import Foundation
import UIKit
import CoreGraphics
import ImageIO
import AMSMB2
import AVFoundation
import OSLog

/// Serial actor that ensures libsmb2 operations never collide concurrently on the same socket
actor SMBClientActor {
    private var client: SMB2Manager?
    private var currentConnectionID: String = ""
    private var currentShareName: String?
    private var activeFolderID: String?
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let fullImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 12
        return cache
    }()
    
    func setActiveFolder(id: String?) {
        self.activeFolderID = id
    }
    
    func getCachedThumbnail(forKey key: NSString) -> UIImage? {
        thumbnailCache.object(forKey: key)
    }
    
    func cacheThumbnail(_ image: UIImage, forKey key: NSString) {
        thumbnailCache.setObject(image, forKey: key)
    }
    
    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "jif", "jfif",
        "png", "heic", "heif", "webp", "avif",
        "gif", "tiff", "tif", "bmp", "ico",
        "jp2", "j2k", "jpf", "jpx",
        "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "pef", "raf"
    ]
    
    private let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v"
    ]
    
    private var supportedMediaExtensions: Set<String> {
        imageExtensions.union(videoExtensions)
    }
    
    /// Connects to the server and enumerates all shared folders automatically
    func connectAndListShares(url: URL, credential: URLCredential, connectionID: String = "") async throws -> [SMBItem] {
        guard let manager = SMB2Manager(url: url, credential: credential) else {
            throw URLError(.badURL)
        }
        
        // Fetch all non-hidden shares from the Mac mini via IPC$
        let shares = try await manager.listShares(enumerateHidden: false)
        self.client = manager
        self.currentConnectionID = connectionID
        self.currentShareName = nil
        
        let items = shares
            .map { share in
                SMBItem(
                    connectionID: connectionID,
                    name: share.name,
                    shareName: share.name,
                    path: "/",
                    isDirectory: true,
                    size: 0,
                    children: nil
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        
        return items
    }
    
    /// Re-fetches the list of shared folders on the currently connected server
    func refreshShares() async throws -> [SMBItem] {
        guard let client else {
            throw URLError(.notConnectedToInternet)
        }
        let shares = try await client.listShares(enumerateHidden: false)
        self.currentShareName = nil
        let connID = self.currentConnectionID
        
        return shares
            .map { share in
                SMBItem(
                    connectionID: connID,
                    name: share.name,
                    shareName: share.name,
                    path: "/",
                    isDirectory: true,
                    size: 0,
                    children: nil
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    private func ensureConnected(to shareName: String) async throws -> SMB2Manager {
        guard let client else {
            throw URLError(.notConnectedToInternet)
        }
        if currentShareName != shareName {
            try await client.connectShare(name: shareName)
            currentShareName = shareName
        }
        return client
    }
    
    func disconnect() async {
        try? await client?.disconnectShare()
        client = nil
        currentConnectionID = ""
        currentShareName = nil
        thumbnailCache.removeAllObjects()
        fullImageCache.removeAllObjects()
    }
    
    /// Scans a directory inside a specific share and returns both its subfolders and its image files
    func scanFolder(shareName: String, at path: String) async throws -> (folders: [SMBItem], pictures: [SMBItem]) {
        try Task.checkCancellation()
        let client = try await ensureConnected(to: shareName)
        try Task.checkCancellation()
        
        let normalizedPath = path == "/" ? "" : path
        let entries = try await client.contentsOfDirectory(atPath: normalizedPath)
        try Task.checkCancellation()
        
        var folders: [SMBItem] = []
        var pictures: [SMBItem] = []
        let connID = self.currentConnectionID
        
        for entry in entries {
            if Task.isCancelled { throw CancellationError() }
            guard let name = entry[.nameKey] as? String,
                  !name.hasPrefix(".") else { continue }
            
            let resourceType = entry[.fileResourceTypeKey] as? URLFileResourceType
            let entryPath = (entry[.pathKey] as? String) ?? (normalizedPath.isEmpty ? name : (normalizedPath as NSString).appendingPathComponent(name))
            let modDate = entry[.contentModificationDateKey] as? Date
            
            if resourceType == .directory {
                folders.append(SMBItem(
                    connectionID: connID,
                    name: name,
                    shareName: shareName,
                    path: entryPath,
                    isDirectory: true,
                    size: 0,
                    modifiedDate: modDate,
                    children: nil
                ))
            } else if resourceType == .regular {
                let ext = (name as NSString).pathExtension.lowercased()
                if supportedMediaExtensions.contains(ext) {
                    let size = Self.extractFileSize(from: entry)
                    pictures.append(SMBItem(
                        connectionID: connID,
                        name: name,
                        shareName: shareName,
                        path: entryPath,
                        isDirectory: false,
                        size: size,
                        modifiedDate: modDate
                    ))
                }
            }
        }
        
        try Task.checkCancellation()
        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        pictures.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        
        return (folders, pictures)
    }
    
    /// Downloads and downsamples a picture/video thumbnail sequentially with 2-tier cache (RAM + Disk).
    /// If expectedFolderID doesn't match the current activeFolderID, it bails immediately.
    func fetchThumbnail(for item: SMBItem, expectedFolderID: String? = nil, maxDimension: CGFloat = 260) async -> UIImage? {
        if Task.isCancelled { return nil }
        if let expected = expectedFolderID, let active = activeFolderID, expected != active {
            return nil
        }
        
        // 1. In-Memory RAM Cache check (Tier 1)
        let memoryCacheKey = "\(item.id)_thumb_\(Int(maxDimension))" as NSString
        if let cached = thumbnailCache.object(forKey: memoryCacheKey) {
            return cached
        }
        
        // 2. Persistent On-Disk Cache check (Tier 2 - Bypasses Wi-Fi / SMB completely!)
        let diskKey = MediaCacheManager.shared.cacheKey(
            for: item.shareName,
            path: item.isVideo ? "\(item.path)_chunkthumb_v1" : item.path,
            dimension: maxDimension,
            connectionID: item.connectionID
        )
        let fallbackKey = !item.connectionID.isEmpty ? MediaCacheManager.shared.cacheKey(
            for: item.shareName,
            path: item.isVideo ? "\(item.path)_chunkthumb_v1" : item.path,
            dimension: maxDimension,
            connectionID: ""
        ) : nil
        if let diskCached = MediaCacheManager.shared.getThumbnail(for: diskKey, fallbackKey: fallbackKey) {
            thumbnailCache.setObject(diskCached, forKey: memoryCacheKey)
            return diskCached
        }
        
        if Task.isCancelled { return nil }
        if let expected = expectedFolderID, let active = activeFolderID, expected != active {
            return nil
        }
        
        do {
            let client = try await ensureConnected(to: item.shareName)
            if Task.isCancelled { return nil }
            if let expected = expectedFolderID, let active = activeFolderID, expected != active {
                return nil
            }
            
            // Videos are processed via streamVideoThumbnail in SMBDirectManager
            if item.isVideo { return nil }
            
            // Photo Thumbnail Handling
            let data = try await client.contents(atPath: item.path)
            if Task.isCancelled { return nil }
            if let expected = expectedFolderID, let active = activeFolderID, expected != active {
                return nil
            }
            
            guard let image = Self.downsample(data: data, maxDimension: maxDimension) ?? AnimatedImageDecoder.decode(from: data) else {
                return nil
            }
            thumbnailCache.setObject(image, forKey: memoryCacheKey)
            MediaCacheManager.shared.saveThumbnail(image, for: diskKey)
            return image
        } catch {
            if !Task.isCancelled {
                AppLog.smb.error("Failed to load thumbnail at \(item.shareName, privacy: .private)/\(item.path, privacy: .private): \(error.localizedDescription)")
            }
            return nil
        }
    }
    
    /// Fetches and streams a video to local disk cache so AVPlayer can play it smoothly
    func fetchVideoURL(for item: SMBItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        let localURL = MediaCacheManager.shared.localVideoURL(for: item)
        if MediaCacheManager.shared.hasCachedVideo(for: item) {
            return localURL
        }
        
        let client = try await ensureConnected(to: item.shareName)
        let partURL = localURL.appendingPathExtension("part")
        
        // Remove any dangling partial download from a previous aborted attempt
        try? FileManager.default.removeItem(at: partURL)
        
        do {
            // Stream directly to temporary .part file on disk (atomic download)
            try await client.downloadItem(atPath: item.path, to: partURL) { bytes, total in
                if Task.isCancelled { return false }
                progress?(bytes, total)
                return true
            }
            
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: partURL)
                throw CancellationError()
            }
            
            // Promote temporary .part file to final local video file atomically
            if FileManager.default.fileExists(atPath: localURL.path) {
                try? FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.moveItem(at: partURL, to: localURL)
        } catch {
            try? FileManager.default.removeItem(at: partURL)
            throw error
        }
        
        // Evict older videos if cache exceeds limit, protecting the newly downloaded one
        MediaCacheManager.shared.evictVideosIfNeeded(keeping: [localURL])
        
        // Upgrade thumbnail cache with real video frame now that it's downloaded
        let diskKey = MediaCacheManager.shared.cacheKey(
            for: item.shareName,
            path: "\(item.path)_vidstream_v7",
            dimension: 260,
            connectionID: item.connectionID
        )
        if let thumb = await MediaCacheManager.shared.generateVideoThumbnail(from: localURL, maxDimension: 260, preferredTime: CMTime(seconds: 5.0, preferredTimescale: 600)) {
            let memoryCacheKey = "\(item.id)_thumb_260" as NSString
            thumbnailCache.setObject(thumb, forKey: memoryCacheKey)
            MediaCacheManager.shared.saveThumbnail(thumb, for: diskKey)
        }
        
        return localURL
    }
    
    func clearMemoryCache() {
        thumbnailCache.removeAllObjects()
        fullImageCache.removeAllObjects()
    }
    
    /// Reads a specific byte range on demand over SMB for video streaming (avoids full file downloads)
    func fetchMediaRange(for item: SMBItem, offset: Int64, length: Int) async throws -> Data {
        let client = try await ensureConnected(to: item.shareName)
        let end = offset + Int64(length)
        let range: Range<Int64> = offset..<end
        return try await client.contents(atPath: item.path, range: range)
    }
    
    /// Queries the remote file size directly if item.size was 0
    func fetchFileSize(for item: SMBItem) async -> Int64 {
        if item.size > 0 { return item.size }
        do {
            let client = try await ensureConnected(to: item.shareName)
            let attrs = try await client.attributesOfItem(atPath: item.path)
            return Self.extractFileSize(from: attrs)
        } catch {
            return 0
        }
    }
    
    private static func extractFileSize(from dict: [URLResourceKey: Any]) -> Int64 {
        (dict[.fileSizeKey] as? NSNumber)?.int64Value ?? (dict[.fileSizeKey] as? Int64) ?? (dict[.fileSizeKey] as? Int).map(Int64.init) ?? 0
    }
    
    /// Downloads the full-resolution image (cached for smooth navigation & slideshow)
    func fetchFullImage(for item: SMBItem) async -> UIImage? {
        // Videos must never be loaded as full images into RAM
        if Task.isCancelled || item.isVideo { return nil }
        
        let cacheKey = "\(item.id)_full" as NSString
        if let cached = fullImageCache.object(forKey: cacheKey) {
            return cached
        }
        
        if Task.isCancelled { return nil }
        
        do {
            let client = try await ensureConnected(to: item.shareName)
            if Task.isCancelled { return nil }
            
            let data = try await client.contents(atPath: item.path)
            if Task.isCancelled { return nil }
            
            guard let image = AnimatedImageDecoder.decode(from: data) else { return nil }
            fullImageCache.setObject(image, forKey: cacheKey)
            return image
        } catch {
            if !Task.isCancelled {
                AppLog.smb.error("Failed to load full image at \(item.shareName, privacy: .private)/\(item.path, privacy: .private): \(error.localizedDescription)")
            }
            return nil
        }
    }
    
    /// Extracts EXIF / camera metadata for an item
    func fetchMetadata(for item: SMBItem) async -> PictureEXIFData? {
        if Task.isCancelled { return nil }
        // For video files, return basic file metadata directly without downloading gigabytes of data into RAM
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
        do {
            let client = try await ensureConnected(to: item.shareName)
            if Task.isCancelled { return nil }
            let data = try await client.contents(atPath: item.path)
            if Task.isCancelled { return nil }
            return ImageMetadataExtractor.extract(from: data, fileName: item.name, fileSize: item.formattedSize)
        } catch {
            return nil
        }
    }
    
    private static func downsample(data: Data, maxDimension: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
