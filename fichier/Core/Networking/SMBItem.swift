//
//  SMBItem.swift
//  fichier
//

import Foundation

nonisolated public struct SMBItem: Identifiable, Hashable, Sendable {
    public var id: String {
        if connectionID.isEmpty {
            return "\(shareName)::\(path)"
        } else {
            return "\(connectionID)|\(shareName)::\(path)"
        }
    }
    public let connectionID: String
    public let name: String
    public let shareName: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let modifiedDate: Date?
    public var children: [SMBItem]?
    
    public init(
        connectionID: String = "",
        name: String,
        shareName: String,
        path: String,
        isDirectory: Bool,
        size: Int64 = 0,
        modifiedDate: Date? = nil,
        children: [SMBItem]? = nil
    ) {
        self.connectionID = connectionID
        self.name = name
        self.shareName = shareName
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedDate = modifiedDate
        self.children = children
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
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v"].contains(ext)
    }
    
    public var isGIF: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ext == "gif"
    }
}
