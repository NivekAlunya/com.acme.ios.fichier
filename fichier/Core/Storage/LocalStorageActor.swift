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
    
    public func activateLocation(_ location: SavedFolderLocation) throws -> StorageItem {
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
        
        let resourceValues = try? resolvedURL.resourceValues(forKeys: [.contentModificationDateKey])
        
        return StorageItem(
            connectionID: location.id,
            name: location.name,
            shareName: location.name,
            path: "",
            isDirectory: true,
            size: 0,
            modifiedDate: resourceValues?.contentModificationDate,
            children: nil,
            localURL: resolvedURL
        )
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
        at folder: StorageItem,
        locationID: String
    ) throws -> (subfolders: [StorageItem], media: [StorageItem]) {
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
        
        var subfolders: [StorageItem] = []
        var media: [StorageItem] = []
        
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
                let item = StorageItem(
                    connectionID: locationID,
                    name: name,
                    shareName: folder.shareName,
                    path: relativePath,
                    isDirectory: true,
                    size: 0,
                    modifiedDate: date,
                    children: nil,
                    localURL: url
                )
                subfolders.append(item)
            } else if supportedImageExtensions.contains(ext) || supportedVideoExtensions.contains(ext) {
                let item = StorageItem(
                    connectionID: locationID,
                    name: name,
                    shareName: folder.shareName,
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
    
    public func fetchThumbnail(for item: StorageItem, maxDimension: CGFloat = 260) async -> UIImage? {
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
    
    // MARK: - Full Image
    
    public func fetchImage(for item: StorageItem) -> UIImage? {
        guard let url = item.localURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    
    // MARK: - Metadata Extraction
    
    public func fetchMetadata(for item: StorageItem) -> PictureEXIFData? {
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
