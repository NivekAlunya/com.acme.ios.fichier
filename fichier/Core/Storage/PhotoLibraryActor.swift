//
//  PhotoLibraryActor.swift
//  fichier
//

import UIKit
import Photos
import AVFoundation

public actor PhotoLibraryActor {
    private let imageManager = PHCachingImageManager()
    
    private var exportDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fichier_video_exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    public init() {}
    
    // MARK: - Authorization
    
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
    
    // MARK: - Root Location
    
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
    
    // MARK: - Content Listing (Smart Albums, User Albums & Assets)
    
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
            fetchResult.enumerateObjects { collection, _, _ in
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                if assets.count > 0 || subtype == .smartAlbumUserLibrary {
                    let albumItem = MediaItem(
                        locationID: StorageLocation.photosLocationID,
                        name: collection.localizedTitle ?? String(localized: titleKey),
                        rootName: "Photos",
                        path: collection.localIdentifier,
                        isDirectory: true,
                        size: Int64(assets.count),
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
        userAlbumsFetch.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            let albumItem = MediaItem(
                locationID: StorageLocation.photosLocationID,
                name: collection.localizedTitle ?? "Album",
                rootName: "Photos",
                path: collection.localIdentifier,
                isDirectory: true,
                size: Int64(assets.count),
                modifiedDate: collection.startDate ?? collection.endDate,
                children: nil,
                localURL: nil,
                folderIconName: "rectangle.stack"
            )
            albums.append(albumItem)
        }
        
        return albums
    }
    
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
            
            let item = MediaItem(
                locationID: StorageLocation.photosLocationID,
                name: defaultName,
                rootName: rootName,
                path: asset.localIdentifier,
                isDirectory: false,
                size: 0,
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
    
    // MARK: - Thumbnails (Race-free with AsyncStream)
    
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
            imageManager.requestImage(
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
        }.makeAsyncIterator()
        
        return await streamIterator.next() ?? nil
    }
    
    // MARK: - Full Image (Race-free with AsyncStream)
    
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
            imageManager.requestImage(
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
        }.makeAsyncIterator()
        
        return await streamIterator.next() ?? nil
    }
    
    // MARK: - Video Playback URL (Safe Temporary Directory with Eviction)
    
    public func fetchVideoURL(for item: MediaItem) async throws -> URL {
        guard let assetID = item.phAssetIdentifier else {
            throw NSError(domain: "PhotoLibraryActor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid asset identifier"])
        }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else {
            throw NSError(domain: "PhotoLibraryActor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Video asset not found"])
        }
        
        purgeOldVideoExports()
        
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        let loadedAsset: AVAsset = try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                guard !hasResumed else { return }
                if let avAsset {
                    hasResumed = true
                    continuation.resume(returning: avAsset)
                } else if let error = info?[PHImageErrorKey] as? Error {
                    hasResumed = true
                    continuation.resume(throwing: error)
                } else {
                    hasResumed = true
                    continuation.resume(throwing: NSError(domain: "PhotoLibraryActor", code: 6, userInfo: [NSLocalizedDescriptionKey: "Unable to load video asset"]))
                }
            }
        }
        
        if let urlAsset = loadedAsset as? AVURLAsset {
            return urlAsset.url
        }
        
        // Composition / Slow-mo export fallback into managed temporary export directory
        let tempURL = exportDirectory.appendingPathComponent("ph_export_\(UUID().uuidString).mov")
        guard let exporter = AVAssetExportSession(asset: loadedAsset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "PhotoLibraryActor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        try await exporter.export(to: tempURL, as: .mov)
        return tempURL
    }
    
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
    
    // MARK: - File Size
    
    public func fetchFileSize(for item: MediaItem) -> Int64 {
        0
    }
    
    // MARK: - Metadata & EXIF (Single Asset IPC Query)
    
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
        let fileName = primaryResource?.filename ?? item.name
        let ext = (fileName as NSString).pathExtension.uppercased()
        let fileFormat = ext.isEmpty ? (asset.mediaType == .video ? "MOV" : "HEIC") : ext
        
        let formattedSize = item.size > 0 ? ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file) : "—"
        
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
