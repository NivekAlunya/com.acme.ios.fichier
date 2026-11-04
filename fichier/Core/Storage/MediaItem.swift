//
//  MediaItem.swift
//  fichier
//

import Foundation

/// Canonical model entity representing a file or directory stored across local folders, iCloud Drive, Photos, or remote SMB shares.
///
/// ### Architecture & Concurrency
/// - **Value Type**: Implemented as an immutable `struct` conforming to `Identifiable`, `Hashable`, and `Sendable`,
///   enabling safe transfer across actor boundaries and concurrency pools.
/// - **Compound Identifier**: Uniquely distinguishes files across multiple servers, shares, and locations via composite keys
///   (e.g., `locationID|rootName::path` or `ph::assetIdentifier`).
/// - **Optimized Equality**: Custom `Equatable` implementation compares shallow metadata and child counts rather than
///   recursively traversing arbitrary directory trees.
nonisolated public struct MediaItem: Identifiable, Hashable, Sendable {
    
    // MARK: - Properties
    
    /// Unique compound identifier distinguishing this item across all storage sources.
    public let id: String
    
    /// The unique identifier of the connection or storage location profile owning this item.
    public let locationID: String
    
    /// The display file or directory name (including extension).
    public let name: String
    
    /// The root share or folder name (e.g. SMB share name or iCloud Drive root).
    public let rootName: String
    
    /// Relative or absolute path of the item within its parent storage container.
    public let path: String
    
    /// Flag indicating whether this item represents a directory/folder.
    public let isDirectory: Bool
    
    /// Total file size in bytes (0 for directories).
    public let size: Int64
    
    /// File content modification timestamp reported by the filesystem.
    public let modifiedDate: Date?
    
    /// Child directory items populated when building hierarchical tree views.
    public var children: [MediaItem]?
    
    /// Local file URL if the item resides directly on device storage or in an app-accessible security-scoped bookmark.
    public let localURL: URL?
    
    /// Local identifier referencing an asset in the user's PhotoKit library (`PHAsset.localIdentifier`).
    public let phAssetIdentifier: String?
    
    /// Explicit video indicator flag override (used when probing PhotoKit asset types).
    public let isMediaVideo: Bool?
    
    /// Custom SF Symbol icon name used for special folder categories (e.g. "icloud", "photo.on.rectangle").
    public let folderIconName: String?
    
    // MARK: - Computed Properties
    
    /// Indicates whether the item originated from the system PhotoKit library.
    public var isPhotoAsset: Bool {
        phAssetIdentifier != nil
    }
    
    /// Alias referencing `rootName` for SMB share contexts.
    public var shareName: String {
        rootName
    }
    
    /// Alias referencing `locationID`.
    public var connectionID: String {
        locationID
    }
    
    // MARK: - Initialization
    
    /// Creates a new `MediaItem` instance, automatically constructing a unique compound identifier.
    ///
    /// ### Identifier Formatting Rules:
    /// - PhotoKit Assets: `ph::{phAssetIdentifier}`
    /// - Unscoped/Root Items: `{rootName}::{path}`
    /// - Scoped Location Items: `{locationID}|{rootName}::{path}`
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
    
    // MARK: - Mutation Helpers
    
    /// Returns a copy of this `MediaItem` updated with a newly discovered file size.
    ///
    /// - Parameter newSize: The updated file size in bytes.
    /// - Returns: A mutated copy of the `MediaItem`.
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
    
    // MARK: - Equatable & Hashable
    
    /// Fast equality check comparing primary identifiers, sizes, modification dates, and immediate child counts.
    ///
    /// Avoids deep $O(N)$ recursive tree traversal on nested directories during SwiftUI diffing passes.
    public static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.size == rhs.size &&
        lhs.modifiedDate == rhs.modifiedDate &&
        (lhs.children?.count == rhs.children?.count) &&
        ((lhs.children == nil) == (rhs.children == nil))
    }
    
    /// Fast path splitting returning zero-allocation substrings separated by `/` or `\`.
    public var normalizedComponents: [Substring] {
        path.split { $0 == "/" || $0 == "\\" }
    }
    
    /// Hashes the item combining its unique compound identifier.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // MARK: - Presentation Formatting
    
    /// Formatted human-readable file size string (e.g. "14.2 MB").
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    /// Localized medium date and short time string representing the last modification date.
    public var formattedDate: String? {
        guard let modifiedDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedDate)
    }
    
    // MARK: - Media Type Discrimination
    
    /// Indicates whether the item is a video file, checking explicit flags or matching file extensions.
    public var isVideo: Bool {
        if let isMediaVideo {
            return isMediaVideo
        }
        let ext = (name as NSString).pathExtension
        return SupportedMediaTypes.isVideo(extension: ext)
    }
    
    /// Indicates whether the item is an animated or static GIF.
    public var isGIF: Bool {
        let ext = (name as NSString).pathExtension
        return SupportedMediaTypes.isGIF(extension: ext)
    }
    
    /// Indicates whether the item is a PDF document.
    public var isPDF: Bool {
        let ext = (name as NSString).pathExtension
        return SupportedMediaTypes.isPDF(extension: ext)
    }
    
    /// Indicates whether the item represents a document format.
    public var isDocument: Bool {
        let ext = (name as NSString).pathExtension
        return SupportedMediaTypes.isDocument(extension: ext)
    }
}
