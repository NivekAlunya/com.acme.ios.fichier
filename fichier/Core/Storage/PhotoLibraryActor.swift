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

    // MARK: - Constants

    /// Default bounded page size when fetching PhotoKit album assets.
    public static let defaultPageSize: Int = 100

    /// Safety cap on total PhotoKit pages iterated by full-album helpers.
    public static let maxPages: Int = 100

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

    /// Fetches a single bounded page of Photos library albums (at root) or assets within an album.
    ///
    /// - Parameters:
    ///   - folder: The folder scope being inspected.
    ///   - sortKey: Global sort attribute passed to `PhotosMediaSource`.
    ///   - sortOrder: Sort direction passed to `PhotosMediaSource`.
    ///   - page: Zero-based page index.
    ///   - pageSize: Maximum number of assets to fetch for this page.
    /// - Returns: A bounded `PhotoLibraryPage` containing subfolders/media and the next page index if more remain.
    /// - Throws: `CancellationError` if cancelled, or `NSError` if Photos permission is denied.
    public func listContentsPage(
        at folder: MediaItem,
        sortBy sortKey: MediaSortKey = .date,
        order sortOrder: MediaSortOrder = .descending,
        page: Int = 0,
        pageSize: Int = PhotoLibraryActor.defaultPageSize
    ) async throws -> PhotoLibraryPage {
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
            return PhotoLibraryPage(subfolders: loadAlbums(), media: [], nextPage: nil)
        }

        let boundedPageSize = max(1, pageSize)
        let targetPage = max(0, page)
        let sourceItems = try await mediaSource.fetchItems(
            in: folder.asMediaSourceItem,
            sortBy: sortKey,
            order: sortOrder,
            page: targetPage,
            pageSize: boundedPageSize
        )
        try Task.checkCancellation()

        let media = sourceItems.map { sourceItem in
            MediaItem(
                sourceItem: sourceItem,
                locationID: StorageLocation.photosLocationID,
                rootName: folder.name
            )
        }
        let nextPage = media.count >= boundedPageSize ? targetPage + 1 : nil
        return PhotoLibraryPage(subfolders: [], media: media, nextPage: nextPage)
    }

    /// Lists contents within the Photos library scope using bounded incremental fetches.
    ///
    /// - Parameter folder: The folder scope being inspected.
    /// - Returns: A tuple of subfolder albums and media items (capped at `Self.maxPages`).
    /// - Throws: `NSError` if permission is revoked, or `CancellationError` if cancelled.
    public func listContents(at folder: MediaItem) async throws -> (subfolders: [MediaItem], media: [MediaItem]) {
        let rootPage = try await listContentsPage(
            at: folder,
            sortBy: .date,
            order: .descending,
            page: 0,
            pageSize: Self.defaultPageSize
        )
        if folder.path.isEmpty {
            return (rootPage.subfolders, rootPage.media)
        }

        var collectedMedia = rootPage.media
        var seenIDs = Set(collectedMedia.map(\.id))
        var nextPage = rootPage.nextPage

        for _ in 1..<Self.maxPages {
            guard let pageIndex = nextPage else { break }
            let page = try await listContentsPage(
                at: folder,
                sortBy: .date,
                order: .descending,
                page: pageIndex,
                pageSize: Self.defaultPageSize
            )
            for item in page.media where seenIDs.insert(item.id).inserted {
                collectedMedia.append(item)
            }
            nextPage = page.nextPage
        }

        return ([], collectedMedia)
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
            for index in 0..<fetchResult.count {
                let collection = fetchResult.object(at: index)
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
        for index in 0..<userAlbumsFetch.count {
            let collection = userAlbumsFetch.object(at: index)
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
            throw NSError(domain: "PhotoLibraryActor", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid asset identifier", comment: "Error message when a photo asset identifier is invalid")])
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
