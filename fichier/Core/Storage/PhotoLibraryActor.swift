//
//  PhotoLibraryActor.swift
//  fichier
//

import UIKit
import Photos
import AVFoundation

public actor PhotoLibraryActor {
    private let imageManager = PHCachingImageManager()
    
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
        
        return MediaItem(
            locationID: StorageLocation.photosLocationID,
            name: String(localized: .Strings.sidebarLocationPhotos),
            rootName: "Photos",
            path: "",
            isDirectory: true,
            size: 0,
            modifiedDate: nil,
            children: nil,
            localURL: nil
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
        
        let smartSubtypes: [(PHAssetCollectionSubtype, LocalizedStringResource)] = [
            (.smartAlbumUserLibrary, .Strings.photosSmartAlbumRecents),
            (.smartAlbumFavorites, .Strings.photosSmartAlbumFavorites),
            (.smartAlbumVideos, .Strings.photosSmartAlbumVideos),
            (.smartAlbumScreenshots, .Strings.photosSmartAlbumScreenshots)
        ]
        
        for (subtype, titleKey) in smartSubtypes {
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
                        localURL: nil
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
                localURL: nil
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
            let originalName: String = PHAssetResource.assetResources(for: asset).first?.filename ?? defaultName
            
            let item = MediaItem(
                locationID: StorageLocation.photosLocationID,
                name: originalName,
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
    
    // MARK: - Thumbnails
    
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
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error
                
                if !hasResumed && (!isDegraded || isCancelled || error != nil) {
                    hasResumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    // MARK: - Full Image (Memory-Optimized Downsampled to Screen Bounds)
    
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
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error
                
                if !hasResumed && (!isDegraded || isCancelled || error != nil) {
                    hasResumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    // MARK: - Video Playback URL
    
    public func fetchVideoURL(for item: MediaItem) async throws -> URL {
        guard let assetID = item.phAssetIdentifier else {
            throw NSError(domain: "PhotoLibraryActor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid asset identifier"])
        }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else {
            throw NSError(domain: "PhotoLibraryActor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Video asset not found"])
        }
        
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
        
        // Composition / Slow-mo export fallback with modern async export
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ph_export_\(UUID().uuidString).mov")
        guard let exporter = AVAssetExportSession(asset: loadedAsset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "PhotoLibraryActor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        try await exporter.export(to: tempURL, as: .mov)
        return tempURL
    }
    
    // MARK: - File Size
    
    public func fetchFileSize(for item: MediaItem) -> Int64 {
        guard let assetID = item.phAssetIdentifier else { return 0 }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else { return 0 }
        
        if let resource = PHAssetResource.assetResources(for: asset).first,
           let size = (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value {
            return size
        }
        return 0
    }
    
    // MARK: - Metadata & EXIF
    
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
        
        let originalResource = PHAssetResource.assetResources(for: asset).first
        let ext = (originalResource?.filename as NSString?)?.pathExtension.uppercased()
        let fileFormat = ext?.isEmpty == false ? ext : (asset.mediaType == .video ? "MOV" : "HEIC")
        
        let sizeBytes: Int64 = (originalResource?.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
        let formattedSize = ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        
        return PictureEXIFData(
            fileName: originalResource?.filename ?? item.name,
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
