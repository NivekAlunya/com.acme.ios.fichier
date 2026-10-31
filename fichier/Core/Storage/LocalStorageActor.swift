//
//  LocalStorageActor.swift
//  fichier
//

import UIKit
import AVFoundation
import ImageIO
import OSLog

public actor LocalStorageActor {
    private var activeSecurityScopedURL: URL?
    private var activeLocationID: String?
    
    private let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp"
    ]
    
    private let supportedVideoExtensions: Set<String> = [
        "mp4", "mov", "m4v"
    ]
    
    public init() {}
    
    deinit {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }
    
    // MARK: - Security-Scoped Bookmark Resolution & Activation
    
    public func activateLocation(_ location: SavedFolderLocation) throws -> (rootItem: MediaItem, updatedBookmark: Data?) {
        deactivateCurrentLocation()
        
        var isStale = false
        let resolvedURL = try URL(
            resolvingBookmarkData: location.bookmarkData,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        
        guard resolvedURL.startAccessingSecurityScopedResource() else {
            throw NSError(
                domain: "LocalStorageActor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to access security-scoped folder: \(location.name)"]
            )
        }
        
        activeSecurityScopedURL = resolvedURL
        activeLocationID = location.id
        
        var updatedBookmark: Data? = nil
        if isStale {
            updatedBookmark = try? resolvedURL.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        
        let resourceValues = try? resolvedURL.resourceValues(forKeys: [.contentModificationDateKey])
        
        let rootItem = MediaItem(
            locationID: location.id,
            name: location.name,
            rootName: location.name,
            path: "",
            isDirectory: true,
            size: 0,
            modifiedDate: resourceValues?.contentModificationDate,
            children: nil,
            localURL: resolvedURL
        )
        
        return (rootItem, updatedBookmark)
    }
    
    public func deactivateCurrentLocation() {
        if let url = activeSecurityScopedURL {
            url.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
            activeLocationID = nil
        }
    }
    
    // MARK: - Folder Contents Enumeration
    
    public func listContents(
        at folder: MediaItem,
        locationID: String
    ) throws -> (subfolders: [MediaItem], media: [MediaItem]) {
        guard let folderURL = folder.localURL else {
            throw NSError(
                domain: "LocalStorageActor",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing localURL for folder: \(folder.name)"]
            )
        }
        
        let keys: [URLResourceKey] = [
            .nameKey,
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isHiddenKey
        ]
        
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        
        var subfolders: [MediaItem] = []
        var media: [MediaItem] = []
        
        for url in contents {
            let resourceValues = try? url.resourceValues(forKeys: Set(keys))
            let isDir = resourceValues?.isDirectory ?? false
            let name = resourceValues?.name ?? url.lastPathComponent
            let size = Int64(resourceValues?.fileSize ?? 0)
            let date = resourceValues?.contentModificationDate
            let ext = url.pathExtension.lowercased()
            
            // Build relative path
            let relativePath = folder.path.isEmpty ? name : "\(folder.path)/\(name)"
            
            if isDir {
                let item = MediaItem(
                    locationID: locationID,
                    name: name,
                    rootName: folder.rootName,
                    path: relativePath,
                    isDirectory: true,
                    size: 0,
                    modifiedDate: date,
                    children: nil,
                    localURL: url
                )
                subfolders.append(item)
            } else if supportedImageExtensions.contains(ext) || supportedVideoExtensions.contains(ext) {
                let item = MediaItem(
                    locationID: locationID,
                    name: name,
                    rootName: folder.rootName,
                    path: relativePath,
                    isDirectory: false,
                    size: size,
                    modifiedDate: date,
                    children: nil,
                    localURL: url
                )
                media.append(item)
            }
        }
        
        subfolders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        media.sort {
            if let d1 = $0.modifiedDate, let d2 = $1.modifiedDate {
                return d1 > d2
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        
        return (subfolders, media)
    }
    
    // MARK: - Thumbnail Generation
    
    public func fetchThumbnail(for item: MediaItem, maxDimension: CGFloat = 260) async -> UIImage? {
        guard let url = item.localURL else { return nil }
        
        if item.isVideo {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
            
            let time = CMTime(seconds: 0.1, preferredTimescale: 600)
            if let (cgImage, _) = try? await generator.image(at: time) {
                return UIImage(cgImage: cgImage)
            }
            return nil
        } else {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return UIImage(contentsOfFile: url.path)
            }
            return UIImage(cgImage: cgImage)
        }
    }
    
    // MARK: - Full Image (Memory Safe with Target Downsampling)
    
    public func fetchImage(for item: MediaItem, maxPixelSize: CGFloat = 2048) -> UIImage? {
        guard let url = item.localURL else { return nil }
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(contentsOfFile: url.path)
        }
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - File Size Query (Offloaded from MainActor)
    
    public func fetchFileSize(for item: MediaItem) -> Int64 {
        guard let url = item.localURL else { return 0 }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return Int64(size ?? 0)
    }
    
    // MARK: - Metadata Extraction
    
    public func fetchMetadata(for item: MediaItem) -> PictureEXIFData? {
        guard let url = item.localURL else { return nil }
        return ImageMetadataExtractor.extract(from: url, fileName: item.name, fileSize: item.formattedSize)
    }
    
    // MARK: - Security-Scoped Bookmark Factory
    
    nonisolated public static func createSavedFolderLocation(from pickedURL: URL) throws -> SavedFolderLocation {
        let didStart = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                pickedURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let bookmarkData = try pickedURL.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        let path = pickedURL.path
        let isICloud = path.contains("Mobile Documents") ||
                       path.contains("com~apple~CloudDocs") ||
                       (try? pickedURL.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
        
        let folderName = pickedURL.lastPathComponent.isEmpty ? "Folder" : pickedURL.lastPathComponent
        
        return SavedFolderLocation(
            name: folderName,
            bookmarkData: bookmarkData,
            isICloud: isICloud
        )
    }
}
