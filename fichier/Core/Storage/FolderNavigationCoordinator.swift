//
//  FolderNavigationCoordinator.swift
//  fichier
//

import Foundation

/// Coordinator managing tree navigation, root boundary detection, and breadcrumb parent derivation.
///
/// Encapsulates hierarchical lookups across SMB shares, local sandboxed directories, and Photos library albums.
@MainActor
public final class FolderNavigationCoordinator {
    
    /// Default initializer.
    public init() {}
    
    /// Determines whether a folder represents the top-level root of its storage backend.
    ///
    /// - Parameter item: The media item folder to inspect.
    /// - Returns: `true` if the folder cannot be navigated above; `false` otherwise.
    public func isRootFolder(_ item: MediaItem) -> Bool {
        if item.locationID == StorageLocation.photosLocationID {
            return item.path.isEmpty
        }
        if item.localURL != nil {
            return item.path.isEmpty
        }
        // SMB root share is "/" or empty
        return item.path == "/" || item.path.isEmpty
    }
    
    /// Recomputes and returns the parent folder of the currently selected folder.
    ///
    /// Employs a fast-path lookup in the existing `folderTree`, falling back to path-string decomposition
    /// (`deriveParentFolder`) when the parent node has not been lazily expanded in the tree.
    ///
    /// - Parameters:
    ///   - selectedFolder: The currently active folder.
    ///   - folderTree: The hierarchical tree nodes currently loaded in memory.
    /// - Returns: The parent `MediaItem` or `nil` if root or not found.
    public func resolveParentFolder(for selectedFolder: MediaItem?, in folderTree: [MediaItem]) -> MediaItem? {
        guard let current = selectedFolder else {
            return nil
        }
        
        if isRootFolder(current) {
            return nil
        }
        
        if let treeParent = findParentInTree(for: current, in: folderTree) {
            return treeParent
        }
        
        return deriveParentFolder(for: current, in: folderTree)
    }
    
    /// Recursively searches the expanded tree hierarchy to locate the immediate parent of a target node.
    ///
    /// - Parameters:
    ///   - target: The child item whose parent is sought.
    ///   - nodes: The tree nodes to search.
    /// - Returns: The parent `MediaItem` if discovered in the tree, or `nil`.
    public func findParentInTree(for target: MediaItem, in nodes: [MediaItem]) -> MediaItem? {
        for node in nodes {
            guard let children = node.children else { continue }
            if children.contains(where: { $0.id == target.id }) {
                return node
            }
            if let found = findParentInTree(for: target, in: children) {
                return found
            }
        }
        return nil
    }
    
    /// Synthesizes a parent `MediaItem` using path-based string surgery when tree metadata is unavailable.
    ///
    /// Sanitizes path components against traversal tokens (`.` and `..`), normalizes path delimiters,
    /// and formats root or directory representations suitable for navigation.
    ///
    /// - Parameters:
    ///   - item: The child folder item.
    ///   - folderTree: The loaded folder tree, used to extract photos root.
    /// - Returns: The derived parent `MediaItem`, or `nil` if already at root.
    public func deriveParentFolder(for item: MediaItem, in folderTree: [MediaItem] = []) -> MediaItem? {
        if item.locationID == StorageLocation.photosLocationID {
            return folderTree.first ?? MediaItem(
                locationID: StorageLocation.photosLocationID,
                name: String(localized: .Strings.sidebarLocationPhotos),
                rootName: "Photos",
                path: "",
                isDirectory: true
            )
        }
        
        if let localURL = item.localURL {
            let parentURL = localURL.deletingLastPathComponent()
            let parentPath = (item.path as NSString).deletingLastPathComponent
            let parentName = parentPath.isEmpty ? item.rootName : parentURL.lastPathComponent
            return MediaItem(
                locationID: item.locationID,
                name: parentName,
                rootName: item.rootName,
                path: parentPath,
                isDirectory: true,
                localURL: parentURL
            )
        }
        
        // SMB: Normalize Windows backslashes and filter traversal tokens
        let normalizedPath = item.path.replacingOccurrences(of: "\\", with: "/")
        let rawComponents = normalizedPath.split(separator: "/").map(String.init)
        let safeComponents = rawComponents.filter { $0 != "." && $0 != ".." && !$0.isEmpty }
        
        guard !safeComponents.isEmpty else { return nil }
        
        if safeComponents.count == 1 {
            return MediaItem(
                locationID: item.locationID,
                name: item.rootName,
                rootName: item.rootName,
                path: "/",
                isDirectory: true
            )
        } else {
            let parentComponents = safeComponents.dropLast()
            let parentPath = "/" + parentComponents.joined(separator: "/")
            let parentName = parentComponents.last ?? item.rootName
            return MediaItem(
                locationID: item.locationID,
                name: parentName,
                rootName: item.rootName,
                path: parentPath,
                isDirectory: true
            )
        }
    }
}
