//
//  PhotoLibraryActor.swift
//  fichier
//

import UIKit
import Photos
import AVFoundation
import FichierKit

/// An isolated actor managing read-only access to the user's system PhotoKit photo and video library.
///
/// ### Architecture & Concurrency Deep-Dive
/// - **FichierKit Delegation**: Delegates PhotoKit authorization, asset enumeration, thumbnail loading,
///   full-resolution loading, and video export resolution to `FichierKit`'s `PhotosMediaSource`,
///   `PhotoThumbnailLoader`, `PhotoFullImageLoader`, and `PhotoVideoLoader`.
/// - **iOS Album Presentation**: Retains iOS-specific localized smart album labels and SF Symbol folder icons.
public actor PhotoLibraryActor {

    // MARK: - Internal Dependencies

    /// Shared `FichierKit` PhotoKit media source handling authorization and asset enumeration.
    private let mediaSource = PhotosMediaSource()

    // MARK: - Initialization

    /// Initializes a photo library actor.
    public init() {}

    // MARK: - Authorization

    /// Checks existing authorization status or triggers an interactive read/write permission prompt.
    ///
    /// - Returns: `true` if authorized or limited access was granted; `false` if denied or restricted.
    public func checkOrRequestAuthorization() async -> Bool {
        let currentStatus = mediaSource.authorizationStatus
        if currentStatus == .authorized || currentStatus == .limited {
            return true
        }
        if currentStatus == .notDetermined {
            let status = await mediaSource.requestAuthorization()
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

        await purgeOldVideoExports()

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

    /// Lists all contents within the Photos library scope: returns album folders at the root, or all assets within a chosen album.
    ///
    /// - Parameter folder: The folder scope being inspected.
    /// - Returns: A tuple of subfolder albums and media items.
    /// - Throws: `NSError` if permission is revoked, or `CancellationError` if cancelled.
    public func listContents(at folder: MediaItem) async throws -> (subfolders: [MediaItem], media: [MediaItem]) {
        try Task.checkCancellation()
        let authorized = await checkOrRequestAuthorization()
        guard authorized else {
            throw NSError(
                domain: "PhotoLibraryActor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: .Strings.photosPermissionDeniedMessage)]
            )
        }
        try Task.checkCancellation()

        if folder.path.isEmpty {
            let albumSourceItems = try await mediaSource.fetchItems(
                in: nil,
                sortBy: .name,
                order: .ascending,
                page: 0,
                pageSize: Int.max
            )
            try Task.checkCancellation()
            let folders = albumSourceItems.map { sourceItem in
                MediaItem(
                    sourceItem: sourceItem,
                    locationID: StorageLocation.photosLocationID,
                    rootName: "Photos",
                    folderIconName: albumIconName(for: sourceItem.name)
                )
            }
            return (folders, [])
        } else {
            let sourceItems = try await mediaSource.fetchItems(
                in: folder.asMediaSourceItem,
                sortBy: .date,
                order: .descending,
                page: 0,
                pageSize: Int.max
            )
            try Task.checkCancellation()
            let media = sourceItems.map { sourceItem in
                MediaItem(
                    sourceItem: sourceItem,
                    locationID: StorageLocation.photosLocationID,
                    rootName: folder.name
                )
            }
            return ([], media)
        }
    }

    /// Helper resolving SF Symbol icons for standard and custom photo albums.
    private func albumIconName(for name: String) -> String {
        switch name {
        case "Recents", String(localized: .Strings.photosSmartAlbumRecents):
            return "clock.arrow.circlepath"
        case "Favorites", String(localized: .Strings.photosSmartAlbumFavorites):
            return "heart.fill"
        case "Videos", String(localized: .Strings.photosSmartAlbumVideos):
            return "video.fill"
        case "Screenshots", String(localized: .Strings.photosSmartAlbumScreenshots):
            return "camera.viewfinder"
        default:
            return "rectangle.stack"
        }
    }

    // MARK: - Asynchronous Image Loading via FichierKit

    /// Retrieves a downscaled thumbnail from `FichierKit.PhotoThumbnailLoader`.
    ///
    /// - Parameters:
    ///   - item: The target `MediaItem`.
    ///   - maxDimension: Maximum pixel bounding box.
    /// - Returns: The final high-quality `UIImage`, or `nil` on failure/cancellation.
    public func fetchThumbnail(for item: MediaItem, maxDimension: CGFloat = 260) async -> UIImage? {
        guard let assetID = item.phAssetIdentifier else { return nil }
        return await PhotoThumbnailLoader.shared.loadThumbnail(
            for: assetID,
            targetSize: CGSize(width: maxDimension, height: maxDimension)
        )
    }

    /// Retrieves a high-resolution display image from `FichierKit.PhotoFullImageLoader`.
    ///
    /// - Parameters:
    ///   - item: Target `MediaItem`.
    ///   - maxPixelSize: Longest pixel edge constraint (default 2048px).
    /// - Returns: A decoded `UIImage`, or `nil`.
    public func fetchImage(for item: MediaItem, maxPixelSize: CGFloat = 2048) async -> UIImage? {
        guard let assetID = item.phAssetIdentifier else { return nil }
        return await PhotoFullImageLoader.shared.loadFullImage(
            for: assetID,
            maxDimension: maxPixelSize
        )
    }

    // MARK: - Video Playback Resolution

    /// Resolves an actionable file system URL for video playback via `FichierKit.PhotoVideoLoader`.
    public func fetchVideoURL(for item: MediaItem) async throws -> URL {
        guard let assetID = item.phAssetIdentifier else {
            throw NSError(domain: "PhotoLibraryActor", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: .Strings.storageErrorInvalidAssetIdentifier)])
        }
        return try await PhotoVideoLoader.shared.loadVideoURL(for: assetID)
    }

    /// Prunes stale temporary video exports.
    public func purgeOldVideoExports() async {
        await PhotoVideoLoader.shared.purgeOldExports()
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
    public func fetchMetadata(for item: MediaItem) async -> PictureEXIFData? {
        guard let assetID = item.phAssetIdentifier else { return nil }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let dimensions = MediaFormatHelper.formatDimensions(width: asset.pixelWidth, height: asset.pixelHeight)
        let megapixels = String(format: "%.1f MP", Double(asset.pixelWidth * asset.pixelHeight) / 1_000_000.0)
        let dateTaken: String? = asset.creationDate.map { MediaFormatHelper.formatDate($0) }

        let primaryResource = PHAssetResource.assetResources(for: asset).first
        let fileName = primaryResource?.originalFilename ?? (asset.value(forKey: "filename") as? String) ?? item.name
        let ext = (fileName as NSString).pathExtension.uppercased()
        let fileFormat = ext.isEmpty ? (asset.mediaType == .video ? "MOV" : "HEIC") : ext

        let sizeInBytes = item.size > 0 ? item.size : ((primaryResource?.value(forKey: "fileSize") as? Int64) ?? Self.estimateFileSize(for: asset))
        let formattedSize = sizeInBytes > 0 ? MediaFormatHelper.formatByteCount(sizeInBytes) : "—"

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
