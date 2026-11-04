//
//  PhotoLibraryActor.swift
//  fichier
//

import UIKit
import Photos
import AVFoundation

/// An isolated actor managing read-only access to the user's system PhotoKit photo and video library.
///
/// ### Architecture & Concurrency Deep-Dive
/// - **Actor Isolation**: Encapsulates `PHCachingImageManager` inside an isolated `actor`, preventing concurrent data races
///   on PhotoKit internal caches and ensuring serialized album enumeration.
/// - **AsyncStream Callback Bridging**: Apple's `requestImage(for:targetSize:contentMode:options:resultHandler:)` invokes its
///   completion closure multiple times (first delivering a low-resolution degraded preview, then the final high-resolution render).
///   To prevent race conditions and duplicate UI updates, this actor bridges requests into `AsyncStream<UIImage?>`,
///   yielding and completing strictly when `!isDegraded || isCancelled || error != nil`.
/// - **Cooperative Request Cancellation**: Registers `continuation.onTermination` on `AsyncStream` so that scrolling past
///   a thumbnail immediately cancels the underlying `PHImageRequestID`.
/// - **Slow-Mo / Composition Video Export**: When a PhotoKit video is an `AVComposition` rather than a direct `AVURLAsset`,
///   it transcode-exports the composition to an ephemeral `.mov` file inside a managed scratch folder.
public actor PhotoLibraryActor {
    
    // MARK: - Internal Dependencies
    
    /// Cached PhotoKit image manager optimizing thumbnail decoding and burst retrieval.
    private lazy var imageManager = PHCachingImageManager()
    
    /// Managed temporary directory for exported video compositions (pruned every hour).
    private var exportDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fichier_video_exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    // MARK: - Initialization
    
    /// Initializes a photo library actor.
    public init() {}
    
    // MARK: - Authorization
    
    /// Checks existing authorization status or triggers an interactive read/write permission prompt.
    ///
    /// - Returns: `true` if authorized or limited access was granted; `false` if denied or restricted.
    public func checkOrRequestAuthorization() async -> Bool {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if currentStatus == .authorized || currentStatus == .limited {
            return true
        }
        if currentStatus == .notDetermined {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return status == .authorized || status == .limited
        }
        return false
    }
    
    // MARK: - Location Activation
    
    /// Activates the Photos library location, verifying permissions and creating the root navigation `MediaItem`.
    ///
    /// - Returns: The root `MediaItem` representing the entire Photos library.
    /// - Throws: `NSError` if permissions were denied.
    public func activateLocation() async throws -> MediaItem {
        let authorized = await checkOrRequestAuthorization()
        guard authorized else {
            throw NSError(
                domain: "PhotoLibraryActor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: .Strings.photosPermissionDeniedMessage)]
            )
        }
        
        purgeOldVideoExports()
        
        return MediaItem(
            locationID: StorageLocation.photosLocationID,
            name: String(localized: .Strings.sidebarLocationPhotos),
            rootName: "Photos",
            path: "",
            isDirectory: true,
            size: 0,
            modifiedDate: nil,
            children: nil,
            localURL: nil,
            folderIconName: "photo.on.rectangle.angled"
        )
    }
    
    // MARK: - Album & Asset Enumeration
    
    /// Lists contents within the Photos library scope: returns album folders at the root, or assets within a chosen album.
    ///
    /// - Parameter folder: The folder scope being inspected.
    /// - Returns: A tuple of subfolder albums and media items.
    /// - Throws: `NSError` if permission is revoked.
    public func listContents(at folder: MediaItem) async throws -> (subfolders: [MediaItem], media: [MediaItem]) {
        let authorized = await checkOrRequestAuthorization()
        guard authorized else {
            throw NSError(
                domain: "PhotoLibraryActor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: .Strings.photosPermissionDeniedMessage)]
            )
        }
        
        if folder.path.isEmpty {
            return (loadAlbums(), [])
        } else {
            let media = loadAssets(forCollectionIdentifier: folder.path, rootName: folder.name)
            return ([], media)
        }
    }
    
    /// Helper computing estimated or exact asset counts for an album collection.
    private func countOfAssets(in collection: PHAssetCollection) -> Int {
        if collection.estimatedAssetCount != NSNotFound {
            return collection.estimatedAssetCount
        }
        return PHAsset.fetchAssets(in: collection, options: nil).count
    }
    
    /// Queries smart albums (Recents, Favorites, Videos, Screenshots) and user-created custom albums.
    private func loadAlbums() -> [MediaItem] {
        var albums: [MediaItem] = []
        
        let smartSubtypes: [(PHAssetCollectionSubtype, LocalizedStringResource, String)] = [
            (.smartAlbumUserLibrary, .Strings.photosSmartAlbumRecents, "clock.arrow.circlepath"),
            (.smartAlbumFavorites, .Strings.photosSmartAlbumFavorites, "heart.fill"),
            (.smartAlbumVideos, .Strings.photosSmartAlbumVideos, "video.fill"),
            (.smartAlbumScreenshots, .Strings.photosSmartAlbumScreenshots, "camera.viewfinder")
        ]
        
        for (subtype, titleKey, icon) in smartSubtypes {
            let fetchResult = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            fetchResult.enumerateObjects { [self] collection, _, _ in
                let count = countOfAssets(in: collection)
                if count > 0 || subtype == .smartAlbumUserLibrary {
                    let albumItem = MediaItem(
                        locationID: StorageLocation.photosLocationID,
                        name: collection.localizedTitle ?? String(localized: titleKey),
                        rootName: "Photos",
                        path: collection.localIdentifier,
                        isDirectory: true,
                        size: Int64(count),
                        modifiedDate: collection.startDate ?? collection.endDate,
                        children: nil,
                        localURL: nil,
                        folderIconName: icon
                    )
                    albums.append(albumItem)
                }
            }
        }
        
        let userAlbumsFetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbumsFetch.enumerateObjects { [self] collection, _, _ in
            let count = countOfAssets(in: collection)
            let albumItem = MediaItem(
                locationID: StorageLocation.photosLocationID,
                name: collection.localizedTitle ?? "Album",
                rootName: "Photos",
                path: collection.localIdentifier,
                isDirectory: true,
                size: Int64(count),
                modifiedDate: collection.startDate ?? collection.endDate,
                children: nil,
                localURL: nil,
                folderIconName: "rectangle.stack"
            )
            albums.append(albumItem)
        }
        
        return albums
    }
    
    /// Queries all photo and video assets belonging to the specified album collection identifier.
    private func loadAssets(forCollectionIdentifier identifier: String, rootName: String) -> [MediaItem] {
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil)
        guard let collection = collections.firstObject else { return [] }
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: collection, options: options)
        
        var mediaItems: [MediaItem] = []
        mediaItems.reserveCapacity(assets.count)
        
        assets.enumerateObjects { asset, _, _ in
            let isVideo = asset.mediaType == .video
            let ext = isVideo ? "mov" : "jpg"
            let defaultName = "IMG_\(asset.localIdentifier.prefix(8)).\(ext)"
            let originalName = (asset.value(forKey: "filename") as? String) ?? defaultName
            let estimatedSize = Self.estimateFileSize(for: asset)
            
            let item = MediaItem(
                locationID: StorageLocation.photosLocationID,
                name: originalName,
                rootName: rootName,
                path: asset.localIdentifier,
                isDirectory: false,
                size: estimatedSize,
                modifiedDate: asset.modificationDate ?? asset.creationDate,
                children: nil,
                localURL: nil,
                phAssetIdentifier: asset.localIdentifier,
                isMediaVideo: isVideo
            )
            mediaItems.append(item)
        }
        
        return mediaItems
    }
    
    // MARK: - Asynchronous Image Loading with AsyncStream
    
    /// Retrieves a downscaled thumbnail from PhotoKit without race conditions.
    ///
    /// - Parameters:
    ///   - item: The target `MediaItem`.
    ///   - maxDimension: Maximum pixel bounding box.
    /// - Returns: The final high-quality `UIImage`, or `nil` on failure/cancellation.
    public func fetchThumbnail(for item: MediaItem, maxDimension: CGFloat = 260) async -> UIImage? {
        guard let assetID = item.phAssetIdentifier else { return nil }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else { return nil }
        
        let targetSize = CGSize(width: maxDimension, height: maxDimension)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        var streamIterator = AsyncStream<UIImage?> { continuation in
            let requestID = imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error
                
                if !isDegraded || isCancelled || error != nil {
                    continuation.yield(image)
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable [weak self] termination in
                if case .cancelled = termination {
                    Task {
                        await self?.cancelImageRequest(requestID)
                    }
                }
            }
        }.makeAsyncIterator()
        
        if let result = await streamIterator.next() {
            return result
        }
        return nil
    }
    
    /// Retrieves a high-resolution display image from PhotoKit.
    ///
    /// - Parameters:
    ///   - item: Target `MediaItem`.
    ///   - maxPixelSize: Longest pixel edge constraint (default 2048px).
    /// - Returns: A decoded `UIImage`, or `nil`.
    public func fetchImage(for item: MediaItem, maxPixelSize: CGFloat = 2048) async -> UIImage? {
        guard let assetID = item.phAssetIdentifier else { return nil }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else { return nil }
        
        let targetSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        var streamIterator = AsyncStream<UIImage?> { continuation in
            let requestID = imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error
                
                if !isDegraded || isCancelled || error != nil {
                    continuation.yield(image)
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable [weak self] termination in
                if case .cancelled = termination {
                    Task {
                        await self?.cancelImageRequest(requestID)
                    }
                }
            }
        }.makeAsyncIterator()
        
        if let result = await streamIterator.next() {
            return result
        }
        return nil
    }
    
    /// Cancels an in-flight `PHImageRequestID`.
    private func cancelImageRequest(_ requestID: PHImageRequestID) {
        imageManager.cancelImageRequest(requestID)
    }
    
    // MARK: - Video Playback Resolution
    
    /// Resolves an actionable file system URL for video playback.
    ///
    /// If the asset is a simple file, returns its direct `AVURLAsset` path. If it represents a slow-motion or HDR composition,
    /// transcode-exports it to `fichier_video_exports` using `AVAssetExportSession`.
    ///
    /// - Parameter item: The target video `MediaItem`.
    /// - Returns: Playable local `URL`.
    /// - Throws: `NSError` if the asset cannot be resolved.
    public func fetchVideoURL(for item: MediaItem) async throws -> URL {
        guard let assetID = item.phAssetIdentifier else {
            throw NSError(domain: "PhotoLibraryActor", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid asset identifier", comment: "Error message when a photo asset identifier is invalid")])
        }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else {
            throw NSError(domain: "PhotoLibraryActor", code: 3, userInfo: [NSLocalizedDescriptionKey: String(localized: "Video asset not found", comment: "Error message when a video asset cannot be found in Photo Library")])
        }
        
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        let stream = AsyncThrowingStream<AVAsset, Error> { continuation in
            imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let avAsset {
                    continuation.yield(avAsset)
                    continuation.finish()
                } else if let error = info?[PHImageErrorKey] as? Error {
                    continuation.finish(throwing: error)
                } else if info?[PHImageResultIsDegradedKey] as? Bool != true {
                    continuation.finish(throwing: NSError(
                        domain: "PhotoLibraryActor",
                        code: 6,
                        userInfo: [NSLocalizedDescriptionKey: String(localized: "Unable to load video asset", comment: "Error message when AVAsset cannot be loaded from Photo Library")]
                    ))
                }
            }
        }
        
        for try await loadedAsset in stream {
            if let urlAsset = loadedAsset as? AVURLAsset {
                return urlAsset.url
            }
            
            // Composition / Slow-mo export fallback into managed temporary export directory
            let tempURL = exportDirectory.appendingPathComponent("ph_export_\(UUID().uuidString).mov")
            guard let exporter = AVAssetExportSession(asset: loadedAsset, presetName: AVAssetExportPresetHighestQuality) else {
                throw NSError(domain: "PhotoLibraryActor", code: 4, userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to create export session", comment: "Error message when AVAssetExportSession cannot be initialized")])
            }
            try await exporter.export(to: tempURL, as: .mov)
            return tempURL
        }
        
        throw NSError(domain: "PhotoLibraryActor", code: 6, userInfo: [NSLocalizedDescriptionKey: String(localized: "Unable to load video asset", comment: "Error message when AVAsset cannot be loaded from Photo Library")])
    }
    
    /// Prunes video composition exports in `fichier_video_exports` that are older than 1 hour.
    public func purgeOldVideoExports() {
        let dir = exportDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let now = Date()
        for file in files {
            if let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               now.timeIntervalSince(date) > 3600 {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    // MARK: - Metadata & Sizing
    
    /// Fetches the file size in bytes using `PHAssetResource`, or estimates based on media type and resolution.
    public func fetchFileSize(for item: MediaItem) -> Int64 {
        guard let assetID = item.phAssetIdentifier else { return 0 }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else { return 0 }
        let resources = PHAssetResource.assetResources(for: asset)
        if let primary = resources.first, let size = primary.value(forKey: "fileSize") as? Int64, size > 0 {
            return size
        }
        return Self.estimateFileSize(for: asset)
    }
    
    /// Estimates file size from pixel count or video duration when exact resource attributes are unavailable.
    private static func estimateFileSize(for asset: PHAsset) -> Int64 {
        if asset.mediaType == .video {
            return Int64(max(200_000, asset.duration * 1_800_000))
        } else {
            let pixels = Double(asset.pixelWidth * asset.pixelHeight)
            return Int64(max(50_000, pixels * 0.35))
        }
    }
    
    /// Queries asset dimensions, megapixels, creation date, and format without triggering heavy file exports.
    ///
    /// - Parameter item: Target `MediaItem`.
    /// - Returns: Populated `PictureEXIFData`.
    public func fetchMetadata(for item: MediaItem) async -> PictureEXIFData? {
        guard let assetID = item.phAssetIdentifier else { return nil }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else { return nil }
        
        let dimensions = "\(asset.pixelWidth) × \(asset.pixelHeight)"
        let megapixels = String(format: "%.1f MP", Double(asset.pixelWidth * asset.pixelHeight) / 1_000_000.0)
        
        let dateTaken: String?
        if let creation = asset.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            dateTaken = formatter.string(from: creation)
        } else {
            dateTaken = nil
        }
        
        let primaryResource = PHAssetResource.assetResources(for: asset).first
        let fileName = primaryResource?.originalFilename ?? (asset.value(forKey: "filename") as? String) ?? item.name
        let ext = (fileName as NSString).pathExtension.uppercased()
        let fileFormat = ext.isEmpty ? (asset.mediaType == .video ? "MOV" : "HEIC") : ext
        
        let sizeInBytes = item.size > 0 ? item.size : ((primaryResource?.value(forKey: "fileSize") as? Int64) ?? Self.estimateFileSize(for: asset))
        let formattedSize = sizeInBytes > 0 ? ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file) : "—"
        
        return PictureEXIFData(
            fileName: fileName,
            fileSize: formattedSize,
            dimensions: dimensions,
            megapixels: megapixels,
            cameraModel: nil,
            lensModel: nil,
            focalLength: nil,
            aperture: nil,
            shutterSpeed: nil,
            iso: nil,
            dateTaken: dateTaken,
            fileFormat: fileFormat
        )
    }
}
