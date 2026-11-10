//
//  MediaItem+FichierKit.swift
//  fichier
//

import Foundation
import FichierKit

extension MediaItem {

    /// Relative path stripped of leading and trailing `/` delimiters for `FichierKit` SMB APIs.
    nonisolated public var smbRelativePath: String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Creates an iOS `MediaItem` from a canonical `FichierKit.MediaSourceItem`, preserving legacy iOS identifiers and SMB leading slashes.
    ///
    /// - Parameters:
    ///   - sourceItem: The canonical source item produced by a `FichierKit` `MediaSource` or `SMBClientProtocol`.
    ///   - locationID: Optional location scope override (preserves guest connection IDs and `StorageLocation.photosLocationID`).
    ///   - rootName: Optional root share, folder, or album name override.
    ///   - folderIconName: Optional SF Symbol icon name for special folder rows.
    nonisolated public init(
        sourceItem: MediaSourceItem,
        locationID: String? = nil,
        rootName: String? = nil,
        folderIconName: String? = nil
    ) {
        if let phAssetIdentifier = sourceItem.phAssetIdentifier {
            self.init(
                locationID: locationID ?? StorageLocation.photosLocationID,
                name: sourceItem.name,
                rootName: rootName ?? "Photos",
                path: phAssetIdentifier,
                isDirectory: sourceItem.type == .folder,
                size: sourceItem.size,
                modifiedDate: sourceItem.modifiedDate,
                children: nil,
                localURL: sourceItem.localURL,
                phAssetIdentifier: phAssetIdentifier,
                isMediaVideo: sourceItem.type == .video,
                folderIconName: folderIconName
            )
            return
        }

        if sourceItem.localURL != nil {
            self.init(
                locationID: locationID ?? sourceItem.sourceID ?? "",
                name: sourceItem.name,
                rootName: rootName ?? sourceItem.localURL?.lastPathComponent ?? "",
                path: sourceItem.path,
                isDirectory: sourceItem.type == .folder,
                size: sourceItem.size,
                modifiedDate: sourceItem.modifiedDate,
                children: nil,
                localURL: sourceItem.localURL,
                phAssetIdentifier: nil,
                isMediaVideo: sourceItem.type == .video ? true : nil,
                folderIconName: folderIconName
            )
            return
        }

        if let smbShare = sourceItem.smbShare {
            let trimmedPath = (sourceItem.smbPath ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let canonicalPath = trimmedPath.isEmpty ? "/" : "/\(trimmedPath)"
            self.init(
                locationID: locationID ?? sourceItem.sourceID ?? "",
                name: sourceItem.name,
                rootName: rootName ?? smbShare,
                path: canonicalPath,
                isDirectory: sourceItem.type == .folder,
                size: sourceItem.size,
                modifiedDate: sourceItem.modifiedDate,
                children: nil,
                localURL: nil,
                phAssetIdentifier: nil,
                isMediaVideo: sourceItem.type == .video ? true : nil,
                folderIconName: folderIconName
            )
            return
        }

        self.init(
            locationID: locationID ?? sourceItem.sourceID ?? StorageLocation.photosLocationID,
            name: sourceItem.name,
            rootName: rootName ?? "Photos",
            path: sourceItem.path,
            isDirectory: sourceItem.type == .folder,
            size: sourceItem.size,
            modifiedDate: sourceItem.modifiedDate,
            children: nil,
            localURL: nil,
            phAssetIdentifier: nil,
            isMediaVideo: sourceItem.type == .video ? true : nil,
            folderIconName: folderIconName
        )
    }

    /// Converts this `MediaItem` into a `FichierKit.MediaSourceItem` for shared package services and streaming helpers.
    nonisolated public var asMediaSourceItem: MediaSourceItem {
        let itemType: MediaItemType
        if isDirectory {
            itemType = .folder
        } else if isVideo {
            itemType = .video
        } else {
            #if !os(tvOS)
            itemType = (isPDF || isDocument) ? .document : .image
            #else
            itemType = .image
            #endif
        }

        if let phAssetIdentifier {
            return MediaSourceItem(
                id: id,
                name: name,
                path: path,
                type: itemType,
                size: size,
                modifiedDate: modifiedDate,
                localURL: localURL,
                phAssetIdentifier: phAssetIdentifier,
                sourceID: locationID
            )
        }

        if let localURL {
            return MediaSourceItem(
                id: id,
                name: name,
                path: path,
                type: itemType,
                size: size,
                modifiedDate: modifiedDate,
                localURL: localURL,
                sourceID: locationID
            )
        }

        if locationID == StorageLocation.photosLocationID {
            return MediaSourceItem(
                id: "album_\(path)",
                name: name,
                path: path,
                type: itemType,
                size: size,
                modifiedDate: modifiedDate,
                sourceID: locationID
            )
        }

        let cleanRelative = smbRelativePath
        let fullPath = cleanRelative.isEmpty ? shareName : "\(shareName)/\(cleanRelative)"
        return MediaSourceItem(
            id: id,
            name: name,
            path: fullPath,
            type: itemType,
            size: size,
            modifiedDate: modifiedDate,
            sourceID: locationID,
            smbShare: shareName,
            smbPath: cleanRelative
        )
    }
}
