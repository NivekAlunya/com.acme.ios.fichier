//
//  MediaItem.swift
//  fichier
//

import Foundation

nonisolated public struct MediaItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let locationID: String
    public let name: String
    public let rootName: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let modifiedDate: Date?
    public var children: [MediaItem]?
    public let localURL: URL?
    public let phAssetIdentifier: String?
    public let isMediaVideo: Bool?
    public let folderIconName: String?
    
    public var isPhotoAsset: Bool {
        phAssetIdentifier != nil
    }
    
    public var shareName: String {
        rootName
    }
    
    public var connectionID: String {
        locationID
    }
    
    public init(
        locationID: String = "",
        name: String,
        rootName: String = "",
        path: String,
        isDirectory: Bool,
        size: Int64 = 0,
        modifiedDate: Date? = nil,
        children: [MediaItem]? = nil,
        localURL: URL? = nil,
        phAssetIdentifier: String? = nil,
        isMediaVideo: Bool? = nil,
        folderIconName: String? = nil
    ) {
        if let phAssetIdentifier {
            self.id = "ph::\(phAssetIdentifier)"
        } else if locationID.isEmpty {
            self.id = "\(rootName)::\(path)"
        } else {
            self.id = "\(locationID)|\(rootName)::\(path)"
        }
        self.locationID = locationID
        self.name = name
        self.rootName = rootName
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedDate = modifiedDate
        self.children = children
        self.localURL = localURL
        self.phAssetIdentifier = phAssetIdentifier
        self.isMediaVideo = isMediaVideo
        self.folderIconName = folderIconName
    }
    
    public func withSize(_ newSize: Int64) -> MediaItem {
        MediaItem(
            locationID: locationID,
            name: name,
            rootName: rootName,
            path: path,
            isDirectory: isDirectory,
            size: newSize,
            modifiedDate: modifiedDate,
            children: children,
            localURL: localURL,
            phAssetIdentifier: phAssetIdentifier,
            isMediaVideo: isMediaVideo,
            folderIconName: folderIconName
        )
    }
    
    public static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
        lhs.id == rhs.id && lhs.size == rhs.size && lhs.modifiedDate == rhs.modifiedDate
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    public var formattedDate: String? {
        guard let modifiedDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedDate)
    }
    
    public var isVideo: Bool {
        if let isMediaVideo {
            return isMediaVideo
        }
        let ext = (name as NSString).pathExtension
        return SupportedMediaTypes.isVideo(extension: ext)
    }
    
    public var isGIF: Bool {
        let ext = (name as NSString).pathExtension
        return SupportedMediaTypes.isGIF(extension: ext)
    }
    
    public var isPDF: Bool {
        let ext = (name as NSString).pathExtension
        return SupportedMediaTypes.isPDF(extension: ext)
    }
    
    public var isDocument: Bool {
        let ext = (name as NSString).pathExtension
        return SupportedMediaTypes.isDocument(extension: ext)
    }
}
