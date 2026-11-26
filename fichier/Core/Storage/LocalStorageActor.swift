//
//  LocalStorageActor.swift
//  fichier
//

import UIKit
import AVFoundation
import ImageIO
import OSLog
import FichierKit
import Wappn

/// An isolated actor managing access to sandboxed local folders, external USB volumes, and iCloud Drive containers.
///
/// ### Architecture & Security Sandbox Deep-Dive
/// - **Security-Scoped Bookmarks**: iOS and iPadOS sandboxes restrict filesystem access outside the app container.
///   When the user picks an external folder via `UIDocuDocumentPmentPickerViewController`, the system yields a security-scoped URL.
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
                userInfo: [NSLocalizedDescriptionKey: String(localized: .Strings.storageErrorLocateFolder(location.name))]
            )
        }
        
        guard resolvedURL.startAccessingSecurityScopedResource() else {
            throw NSError(
                domain: "LocalStorageActor",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(localized: .Strings.storageErrorPermissionExpired(location.name))]
            )
        }
        
        activeSecurityScopedURL = resolvedURL
        activeLocationID = location.id
        
        var updatedBookmark: Data?
        if isStale {
            // Attempt minimal bookmark refresh first, falling back to standard bookmark options
            do {
                updatedBookmark = try resolvedURL.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                do {
                    updatedBookmark = try resolvedURL.bookmarkData(
                        options: [],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                } catch {
                    logw("Failed to refresh stale security-scoped bookmark: \(error.localizedDescription)")
                }
            }
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
                userInfo: [NSLocalizedDescriptionKey: String(localized: .Strings.storageErrorMissingLocalUrl(folder.name))]
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
                userInfo: [NSLocalizedDescriptionKey: String(localized: .Strings.storageErrorReadContentsFailed(folder.name))]
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
                await MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                return thumb
            }
            return nil
        } else if item.isPDF {
            if let thumb = MediaCacheManager.shared.generatePDFThumbnail(from: url, maxDimension: targetDimension) {
                await MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                return thumb
            }
            return nil
        } else {
            guard let thumb = SMBImageLoader.decodeDownsampledImage(from: url, maxPixelSize: targetDimension) else {
                return nil
            }
            await MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
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
        return SMBImageLoader.decodeDownsampledImage(from: url, maxPixelSize: maxPixelSize)
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
    
    // MARK: - File Management Operations
    
    /// Creates a new subfolder inside a local or iCloud directory.
    ///
    /// - Parameters:
    ///   - name: The user-specified folder name.
    ///   - parentFolder: The parent directory `MediaItem`.
    ///   - locationID: The owning storage location identifier.
    /// - Returns: The newly created folder `MediaItem`.
    /// - Throws: `FileOperationError` or filesystem errors.
    public func createFolder(
        named name: String,
        in parentFolder: MediaItem,
        locationID: String
    ) throws -> MediaItem {
        let trimmed = try FileOperationError.validateName(name)
        
        guard let parentURL = parentFolder.localURL else {
            throw FileOperationError.missingURL(parentFolder.name)
        }
        
        let standardizedParent = parentURL.standardizedFileURL
        let newFolderURL = standardizedParent.appendingPathComponent(trimmed, isDirectory: true).standardizedFileURL
        
        guard newFolderURL.deletingLastPathComponent().path == standardizedParent.path else {
            throw FileOperationError.invalidName(name)
        }
        
        if FileManager.default.fileExists(atPath: newFolderURL.path) {
            throw FileOperationError.itemAlreadyExists(trimmed)
        }
        
        try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: false, attributes: nil)
        
        let relativePath = parentFolder.path.isEmpty ? trimmed : "\(parentFolder.path)/\(trimmed)"
        return MediaItem(
            locationID: locationID,
            name: trimmed,
            rootName: parentFolder.rootName,
            path: relativePath,
            isDirectory: true,
            size: 0,
            modifiedDate: Date(),
            children: nil,
            localURL: newFolderURL
        )
    }
    
    /// Moves a collection of media items or subfolders to the macOS/iOS Trash.
    ///
    /// - Parameter items: The items to remove.
    /// - Throws: `FileOperationError` or filesystem errors.
    public func deleteItems(_ items: [MediaItem]) throws {
        let fileManager = FileManager.default
        // Pre-flight check: ensure all items exist with valid URLs
        for item in items {
            guard let url = item.localURL else {
                throw FileOperationError.missingURL(item.name)
            }
            guard fileManager.fileExists(atPath: url.path) else {
                throw FileOperationError.missingURL(item.name)
            }
        }
        for item in items {
            if let url = item.localURL {
                do {
                    try fileManager.trashItem(at: url, resultingItemURL: nil)
                } catch let error as CocoaError where error.code == .featureUnsupported {
                    // Fallback to permanent removal if volume doesn't have a Trash container
                    try fileManager.removeItem(at: url)
                } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == 3328 {
                    try fileManager.removeItem(at: url)
                }
            }
        }
    }
    
    /// Moves a collection of media items or folders into a target destination folder.
    ///
    /// - Parameters:
    ///   - items: The items to move.
    ///   - destinationFolder: The destination folder `MediaItem`.
    /// - Throws: `FileOperationError` or filesystem errors.
    public func moveItems(_ items: [MediaItem], to destinationFolder: MediaItem) throws {
        guard let destURL = destinationFolder.localURL else {
            throw FileOperationError.missingURL(destinationFolder.name)
        }
        
        let fileManager = FileManager.default
        let standardizedDestPath = destURL.standardizedFileURL.path
        
        // Pre-flight validation: check all sources and destination collisions before mutating
        var plannedMoves: [(sourceURL: URL, targetURL: URL)] = []
        var plannedTargets = Set<String>()
        for item in items {
            guard let sourceURL = item.localURL else {
                throw FileOperationError.missingURL(item.name)
            }
            
            let standardizedSourcePath = sourceURL.standardizedFileURL.path
            
            // Cannot move into self or child folder
            if item.isDirectory {
                if standardizedDestPath == standardizedSourcePath ||
                   standardizedDestPath.hasPrefix(standardizedSourcePath + "/") {
                    throw FileOperationError.cannotMoveIntoSelf
                }
            }
            
            // Skip if already in the destination folder
            let sourceParentPath = sourceURL.deletingLastPathComponent().standardizedFileURL.path
            if sourceParentPath == standardizedDestPath {
                continue
            }
            
            let targetURL = destURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: item.isDirectory)
            let targetPath = targetURL.standardizedFileURL.path
            if fileManager.fileExists(atPath: targetPath) || plannedTargets.contains(targetPath) {
                throw FileOperationError.itemAlreadyExists(sourceURL.lastPathComponent)
            }
            plannedTargets.insert(targetPath)
            plannedMoves.append((sourceURL, targetURL))
        }
        
        // Execute moves after full validation pass
        for move in plannedMoves {
            try fileManager.moveItem(at: move.sourceURL, to: move.targetURL)
        }
    }
    
    /// Renames a media item or folder within its parent directory on local or iCloud storage.
    ///
    /// - Parameters:
    ///   - item: The `MediaItem` to rename.
    ///   - newName: The new filename or directory name.
    /// - Returns: The updated `MediaItem`.
    /// - Throws: `FileOperationError` or filesystem errors.
    public func renameItem(_ item: MediaItem, to newName: String) throws -> MediaItem {
        let trimmed = try FileOperationError.validateName(newName)
        
        guard let sourceURL = item.localURL else {
            throw FileOperationError.missingURL(item.name)
        }
        
        if trimmed == item.name {
            return item
        }
        
        let parentURL = sourceURL.deletingLastPathComponent().standardizedFileURL
        let targetURL = parentURL.appendingPathComponent(trimmed, isDirectory: item.isDirectory).standardizedFileURL
        
        guard targetURL.deletingLastPathComponent().path == parentURL.path else {
            throw FileOperationError.invalidName(newName)
        }
        
        let isCaseOnlyRename = sourceURL.path.caseInsensitiveCompare(targetURL.path) == .orderedSame
        let fileManager = FileManager.default
        if !isCaseOnlyRename && fileManager.fileExists(atPath: targetURL.path) {
            throw FileOperationError.itemAlreadyExists(trimmed)
        }
        
        if isCaseOnlyRename {
            let tempURL = parentURL.appendingPathComponent(".rename_\(UUID().uuidString).tmp", isDirectory: item.isDirectory)
            try fileManager.moveItem(at: sourceURL, to: tempURL)
            do {
                try fileManager.moveItem(at: tempURL, to: targetURL)
            } catch {
                do {
                    try fileManager.moveItem(at: tempURL, to: sourceURL)
                } catch let rollbackError {
                    loge("Failed to roll back case-only rename from temp file: \(rollbackError.localizedDescription)")
                }
                throw error
            }
        } else {
            try fileManager.moveItem(at: sourceURL, to: targetURL)
        }
        
        let parentRelativePath = (item.path as NSString).deletingLastPathComponent
        let normalizedParent = (parentRelativePath == "." ? "" : parentRelativePath)
        let newRelativePath = normalizedParent.isEmpty ? trimmed : "\(normalizedParent)/\(trimmed)"
        
        return MediaItem(
            locationID: item.locationID,
            name: trimmed,
            rootName: item.rootName,
            path: newRelativePath,
            isDirectory: item.isDirectory,
            size: item.size,
            modifiedDate: Date(),
            children: item.children,
            localURL: targetURL,
            phAssetIdentifier: item.phAssetIdentifier,
            isMediaVideo: item.isMediaVideo,
            folderIconName: item.folderIconName
        )
    }
    
    /// Lists immediate child subfolders within a local or iCloud directory.
    ///
    /// - Parameters:
    ///   - folder: The parent folder `MediaItem`.
    ///   - locationID: Owning storage location identifier.
    /// - Returns: An array of immediate subfolder `MediaItem`s.
    public func listSubfolders(at folder: MediaItem, locationID: String) throws -> [MediaItem] {
        let (subfolders, _) = try listContents(at: folder, locationID: locationID)
        return subfolders
    }
}
