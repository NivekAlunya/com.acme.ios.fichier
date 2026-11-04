//
//  LocalStorageActor.swift
//  fichier
//

import UIKit
import AVFoundation
import ImageIO
import OSLog

/// An isolated actor managing access to sandboxed local folders, external USB volumes, and iCloud Drive containers.
///
/// ### Architecture & Security Sandbox Deep-Dive
/// - **Security-Scoped Bookmarks**: iOS and iPadOS sandboxes restrict filesystem access outside the app container.
///   When the user picks an external folder via `UIDocumentPickerViewController`, the system yields a security-scoped URL.
///   To retain access across app terminations, this actor converts picked URLs into persistent security-scoped bookmark data (`options: .minimalBookmark`).
/// - **Resource Access Lifecycle**: Calls `startAccessingSecurityScopedResource()` during activation and guarantees
///   balanced `stopAccessingSecurityScopedResource()` calls during deactivation or `deinit`.
/// - **Stale Bookmark Refresh**: Detects when filesystem reorganization marks bookmarks as stale (`bookmarkDataIsStale: &isStale`),
///   regenerating new bookmark payloads on the fly without user interruption.
/// - **iCloud Ubiquity Detection**: Inspects path tokens (`Mobile Documents`, `com~apple~CloudDocs`) and `.isUbiquitousItemKey`
///   to classify locations as iCloud Drive or local storage.
public actor LocalStorageActor {
    
    // MARK: - State Properties
    
    /// The currently active security-scoped folder URL being accessed by the application.
    private var activeSecurityScopedURL: URL?
    
    /// The unique identifier of the active saved location profile.
    private var activeLocationID: String?
    
    // MARK: - Initialization & Deinitialization
    
    /// Initializes the local storage actor.
    public init() {}
    
    /// Ensures security-scoped resource access is cleanly terminated if the actor is released.
    deinit {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }
    
    // MARK: - Security-Scoped Bookmark Resolution & Activation
    
    /// Resolves and activates a security-scoped bookmark for a local or iCloud Drive folder.
    ///
    /// Distinguishes between stale bookmarks, unmounted external drives, and revoked OS permissions,
    /// returning the activated root `MediaItem` along with any refreshed bookmark data.
    ///
    /// ### Complex Code Breakdown:
    /// - **Resolution**: Uses `URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)` with `.withoutUI`.
    /// - **Access Grant**: Invokes `startAccessingSecurityScopedResource()`. If rejected, raises a localized error prompting folder re-selection.
    /// - **Stale Recovery**: If `isStale == true`, creates an updated bookmark data payload using `.minimalBookmark`.
    ///
    /// - Parameter location: The saved folder location model containing bookmark data.
    /// - Returns: A tuple of the root `MediaItem` and an optional updated `Data` bookmark if refreshed.
    /// - Throws: `NSError` if the folder cannot be located or permission was revoked.
    public func activateLocation(_ location: SavedFolderLocation) throws -> (rootItem: MediaItem, updatedBookmark: Data?) {
        deactivateCurrentLocation()
        
        var isStale = false
        let resolvedURL: URL
        do {
            resolvedURL = try URL(
                resolvingBookmarkData: location.bookmarkData,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw NSError(
                domain: "LocalStorageActor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Unable to locate folder '\(location.name)'. If it is on an external drive, ensure the drive is connected.", comment: "Error message when resolving security-scoped bookmark fails")]
            )
        }
        
        guard resolvedURL.startAccessingSecurityScopedResource() else {
            throw NSError(
                domain: "LocalStorageActor",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Access permission expired for folder '\(location.name)'. Please re-select the folder in Settings or Sidebar.", comment: "Error message when security-scoped resource access is rejected")]
            )
        }
        
        activeSecurityScopedURL = resolvedURL
        activeLocationID = location.id
        
        var updatedBookmark: Data? = nil
        if isStale {
            // Attempt minimal bookmark refresh first, falling back to standard bookmark options
            updatedBookmark = (try? resolvedURL.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )) ?? (try? resolvedURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ))
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
    
    /// Relinquishes security-scoped access to the currently active folder.
    public func deactivateCurrentLocation() {
        if let url = activeSecurityScopedURL {
            url.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
            activeLocationID = nil
        }
    }
    
    // MARK: - Folder Contents Enumeration
    
    /// Enumerates subfolders and supported media files within a security-scoped local or iCloud folder.
    ///
    /// - Parameters:
    ///   - folder: The parent `MediaItem` representing the directory to inspect.
    ///   - locationID: The owning storage location identifier.
    /// - Returns: A tuple containing sorted subfolders and media items.
    /// - Throws: `NSError` if directory reading fails or volume is unmounted.
    public func listContents(
        at folder: MediaItem,
        locationID: String
    ) throws -> (subfolders: [MediaItem], media: [MediaItem]) {
        guard let folderURL = folder.localURL else {
            throw NSError(
                domain: "LocalStorageActor",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Missing local URL for folder: \(folder.name)", comment: "Error message when local URL is missing for a folder")]
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
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw NSError(
                domain: "LocalStorageActor",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Cannot read contents of '\(folder.name)'. Please verify the folder or external volume is connected.", comment: "Error message when reading contents of a local folder fails")]
            )
        }
        
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
            } else if SupportedMediaTypes.isSupported(extension: ext) {
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
    
    /// Generates or loads a cached thumbnail for a local or iCloud file.
    ///
    /// Checks persistent disk cache (Tier 2) first to avoid repeated AVAsset or CoreMedia decompression on local videos.
    ///
    /// - Parameters:
    ///   - item: The target `MediaItem`.
    ///   - maxDimension: Maximum thumbnail pixel size.
    /// - Returns: A decoded `UIImage`, or `nil` on failure.
    public func fetchThumbnail(for item: MediaItem, maxDimension: CGFloat = MediaCacheManager.standardThumbnailDimension) async -> UIImage? {
        guard let url = item.localURL else { return nil }
        
        // Check persistent disk cache before invoking heavy image/video decoding
        let subPath = item.isVideo ? "\(item.path)_vidstream_v7" : item.path
        let (diskKey, fallbackKey, legacyKey) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: subPath,
            dimension: maxDimension,
            connectionID: item.connectionID
        )
        if let diskCached = await MediaCacheManager.shared.getThumbnailAsync(for: diskKey, fallbackKey: fallbackKey, legacyKey: legacyKey) {
            return diskCached
        }
        
        let targetDimension = MediaCacheManager.standardThumbnailDimension
        if item.isVideo {
            if let thumb = await MediaCacheManager.shared.generateVideoThumbnail(from: url, maxDimension: targetDimension) {
                MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                return thumb
            }
            return nil
        } else if item.isPDF {
            if let thumb = MediaCacheManager.shared.generatePDFThumbnail(from: url, maxDimension: targetDimension) {
                MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                return thumb
            }
            return nil
        } else {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: targetDimension
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return UIImage(contentsOfFile: url.path)
            }
            let thumb = UIImage(cgImage: cgImage)
            MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
            return thumb
        }
    }
    
    // MARK: - Full Image (Memory Safe with Target Downsampling)
    
    /// Loads a full-resolution image from disk downsampled to a maximum bounding box (default 2048px).
    ///
    /// Uses `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` to avoid
    /// allocating 100+ megabytes of uncompressed bitmap memory for high-megapixel camera photos.
    ///
    /// - Parameters:
    ///   - item: The target photo `MediaItem`.
    ///   - maxPixelSize: Longest pixel constraint edge.
    /// - Returns: A decoded `UIImage`, or `nil`.
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
    
    // MARK: - File Size Query
    
    /// Reads exact file size in bytes from the filesystem URL resource keys.
    public func fetchFileSize(for item: MediaItem) -> Int64 {
        guard let url = item.localURL else { return 0 }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return Int64(size ?? 0)
    }
    
    // MARK: - Metadata Extraction
    
    /// Parses camera and EXIF metadata directly from the local file URL using `ImageMetadataExtractor`.
    public func fetchMetadata(for item: MediaItem) -> PictureEXIFData? {
        guard let url = item.localURL else { return nil }
        return ImageMetadataExtractor.extract(from: url, fileName: item.name, fileSize: item.formattedSize)
    }
    
    // MARK: - Security-Scoped Bookmark Factory
    
    /// Generates a persistent security-scoped bookmark representation from a user-selected folder URL.
    ///
    /// - Parameter pickedURL: The URL returned by `UIDocumentPickerViewController`.
    /// - Returns: A persistent `SavedFolderLocation` ready for serialization into `UserDefaults`.
    /// - Throws: An error if bookmark creation fails.
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
