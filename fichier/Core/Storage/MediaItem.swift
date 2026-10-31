//
//  MediaItem.swift
//  fichier
//

import Foundation

nonisolated public struct MediaItem: Identifiable, Hashable, Sendable {
    public var id: String {
        if let phAssetIdentifier {
            return "ph::\(phAssetIdentifier)"
        }
        if locationID.isEmpty {
            return "\(rootName)::\(path)"
        } else {
            return "\(locationID)|\(rootName)::\(path)"
        }
    }
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
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v"].contains(ext)
    }
    
    public var isGIF: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ext == "gif"
    }
}
