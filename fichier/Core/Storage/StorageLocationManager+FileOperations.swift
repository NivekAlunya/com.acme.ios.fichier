//
//  StorageLocationManager+FileOperations.swift
//  fichier
//

import Foundation
import SwiftUI
import FichierKit

extension StorageLocationManager {
    
    // MARK: - File Management Capabilities
    
    /// Indicates whether the currently active folder supports file management operations (creation, moving, deletion).
    public var canManageCurrentFolder: Bool {
        guard let location = currentLocation else { return false }
        switch location.kind {
        case .localFolder, .iCloudFolder:
            return selectedFolder?.localURL != nil
        case .smb:
            return selectedFolder != nil && !(selectedFolder?.shareName.isEmpty ?? true)
        case .photos:
            return false
        }
    }
    
    /// Checks whether an individual media item supports filesystem manipulation.
    ///
    /// - Parameter item: The item to inspect.
    /// - Returns: `true` if the item resides on local, iCloud, or remote SMB storage.
    public func canManageItem(_ item: MediaItem) -> Bool {
        guard let location = currentLocation else { return false }
        switch location.kind {
        case .localFolder, .iCloudFolder:
            return item.localURL != nil
        case .smb:
            return !item.shareName.isEmpty
        case .photos:
            return false
        }
    }
    
    // MARK: - Folder Creation
    
    /// Creates a new subfolder in the specified or currently selected directory and refreshes folder contents.
    ///
    /// - Parameters:
    ///   - name: The name of the new directory to create.
    ///   - targetFolder: Optional parent folder; defaults to `selectedFolder`.
    /// - Returns: The newly created folder `MediaItem`.
    /// - Throws: `FileOperationError` if the name is invalid, already exists, or the backend is unsupported.
    @discardableResult
    public func createFolder(named name: String, in targetFolder: MediaItem? = nil) async throws -> MediaItem {
        guard let current = targetFolder ?? selectedFolder else {
            throw FileOperationError.unsupportedStorage
        }
        
        let createdFolder: MediaItem
        if current.localURL != nil {
            createdFolder = try await localWorker.createFolder(
                named: name,
                in: current,
                locationID: current.locationID
            )
        } else if !current.shareName.isEmpty {
            createdFolder = try await worker.createFolder(
                named: name,
                inShare: current.shareName,
                atPath: current.path
            )
        } else {
            throw FileOperationError.unsupportedStorage
        }
        
        recordMutation()
        await refreshExpandedTreeBranches()
        
        if let reloadTarget = selectedFolder {
            await selectAndLoadFolder(reloadTarget)
        }
        return createdFolder
    }
    
    // MARK: - Deletion / Move to Trash
    
    /// Moves a collection of items (files or subfolders) to the system Trash for local files,
    /// or permanently deletes them from remote SMB shares.
    ///
    /// - Parameter items: The items to delete.
    /// - Throws: `FileOperationError` if deletion fails or storage is unsupported.
    public func deleteItems(_ items: [MediaItem]) async throws {
        guard !items.isEmpty else { return }
        
        let localItems = items.filter { $0.localURL != nil }
        let smbItems = items.filter { $0.localURL == nil && !$0.shareName.isEmpty }
        
        guard localItems.count + smbItems.count == items.count else {
            throw FileOperationError.unsupportedStorage
        }
        
        if !localItems.isEmpty {
            try await localWorker.deleteItems(localItems)
        }
        if !smbItems.isEmpty {
            try await worker.deleteItems(smbItems)
        }
        
        for item in items where FavoritesManager.shared.isFavorite(item) {
            FavoritesManager.shared.toggleFavorite(item)
        }
        
        // Remove deleted items in-place from current view to preserve scroll position without full reload
        let deletedIDs = Set(items.map(\.id))
        withAnimation(.snappy) {
            self.pictures.removeAll(where: { deletedIDs.contains($0.id) })
            self.currentFolders.removeAll(where: { deletedIDs.contains($0.id) })
        }
        
        if items.contains(where: \.isDirectory) {
            self.folderTree = removeNodesFromTree(in: self.folderTree, targetIDs: deletedIDs)
            recordMutation()
            await refreshExpandedTreeBranches()
        }
    }
    
    // MARK: - Move Items
    
    /// Moves a collection of items into a chosen destination folder.
    ///
    /// - Parameters:
    ///   - items: The items to move.
    ///   - destinationFolder: The target destination folder.
    /// - Throws: `FileOperationError` if moving fails or crossing distinct storage boundaries.
    public func moveItems(_ items: [MediaItem], to destinationFolder: MediaItem) async throws {
        guard !items.isEmpty else { return }
        
        if destinationFolder.localURL != nil {
            guard items.allSatisfy({ $0.localURL != nil }) else {
                throw FileOperationError.unsupportedStorage
            }
            try await localWorker.moveItems(items, to: destinationFolder)
        } else if !destinationFolder.shareName.isEmpty {
            guard items.allSatisfy({ $0.localURL == nil && $0.shareName == destinationFolder.shareName && $0.locationID == destinationFolder.locationID }) else {
                throw FileOperationError.unsupportedStorage
            }
            try await worker.moveItems(items, to: destinationFolder)
        } else {
            throw FileOperationError.unsupportedStorage
        }
        
        // Remove moved items in-place from current view to preserve scroll position
        let movedIDs = Set(items.map(\.id))
        withAnimation(.snappy) {
            self.pictures.removeAll(where: { movedIDs.contains($0.id) })
            self.currentFolders.removeAll(where: { movedIDs.contains($0.id) })
        }
        
        if items.contains(where: \.isDirectory) {
            self.folderTree = removeNodesFromTree(in: self.folderTree, targetIDs: movedIDs)
            recordMutation()
            await refreshExpandedTreeBranches()
        }
    }
    
    // MARK: - Rename Item
    
    /// Renames a media item (file or subfolder) within its parent directory and updates the UI state in-place.
    ///
    /// - Parameters:
    ///   - item: The target `MediaItem` to rename.
    ///   - newName: The new name (with extension for files).
    /// - Returns: The mutated `MediaItem` with updated identifiers and filesystem path.
    /// - Throws: `FileOperationError` if the name is invalid, storage is unsupported, or a name collision occurs.
    @discardableResult
    public func renameItem(_ item: MediaItem, to newName: String) async throws -> MediaItem {
        guard canManageItem(item) else {
            throw FileOperationError.unsupportedStorage
        }
        
        let trimmed = try FileOperationError.validateName(newName)
        
        guard trimmed != item.name else {
            return item
        }
        
        let renamedItem: MediaItem
        if item.localURL != nil {
            renamedItem = try await localWorker.renameItem(item, to: trimmed)
            await MediaCacheManager.shared.migrateThumbnailCache(from: item, to: renamedItem)
            let oldMemoryKey = "\(item.id)_thumb" as NSString
            let newMemoryKey = "\(renamedItem.id)_thumb" as NSString
            if let memCached = worker.getCachedThumbnail(forKey: oldMemoryKey) {
                worker.cacheThumbnail(memCached, forKey: newMemoryKey)
            }
        } else if !item.shareName.isEmpty {
            renamedItem = try await worker.renameItem(item, to: trimmed)
        } else {
            throw FileOperationError.unsupportedStorage
        }

        // Migrate metadata detail and video resume positions
        if let detail = MediaDetailStore.shared.cachedDetail(for: item.id) {
            MediaDetailStore.shared.registerDetail(detail, for: renamedItem.id)
        }
        if item.isVideo {
            VideoPlaybackStore.shared.migratePosition(from: item.id, to: renamedItem.id)
        }
        
        // Update in-place in pictures and currentFolders to preserve scroll position
        withAnimation(.snappy) {
            if let idx = self.pictures.firstIndex(where: { $0.id == item.id }) {
                self.pictures[idx] = renamedItem
            }
            if let idx = self.currentFolders.firstIndex(where: { $0.id == item.id }) {
                self.currentFolders[idx] = renamedItem
            }
        }

        self.thumbnailVersions[renamedItem.id, default: 0] += 1
        
        // Update favorite if present
        if FavoritesManager.shared.isFavorite(item) {
            FavoritesManager.shared.toggleFavorite(item)
            FavoritesManager.shared.toggleFavorite(renamedItem)
        }
        
        if item.isDirectory {
            self.folderTree = renameNodeInTree(in: self.folderTree, targetID: item.id, renamedItem: renamedItem)
            if let currentSelected = self.selectedFolder {
                if currentSelected.id == item.id {
                    self.selectedFolder = renamedItem
                } else if currentSelected.path.hasPrefix(item.path + "/") {
                    let relativeSuffix = String(currentSelected.path.dropFirst(item.path.count + 1))
                    let newSelectedPath = "\(renamedItem.path)/\(relativeSuffix)"
                    let newSelectedURL = renamedItem.localURL?.appendingPathComponent(relativeSuffix, isDirectory: true)
                    self.selectedFolder = MediaItem(
                        locationID: currentSelected.locationID,
                        name: currentSelected.name,
                        rootName: currentSelected.rootName,
                        path: newSelectedPath,
                        isDirectory: currentSelected.isDirectory,
                        size: currentSelected.size,
                        modifiedDate: currentSelected.modifiedDate,
                        children: currentSelected.children,
                        localURL: newSelectedURL,
                        phAssetIdentifier: currentSelected.phAssetIdentifier,
                        isMediaVideo: currentSelected.isMediaVideo,
                        folderIconName: currentSelected.folderIconName
                    )
                }
            }
            recordMutation()
            await refreshExpandedTreeBranches()
        }
        
        return renamedItem
    }
    
    /// Recursively renames a directory node inside the hierarchical folder tree and updates descendant paths.
    private func renameNodeInTree(in nodes: [MediaItem], targetID: String, renamedItem: MediaItem) -> [MediaItem] {
        var updated = nodes
        for idx in updated.indices {
            if updated[idx].id == targetID {
                var replacement = renamedItem
                if let children = updated[idx].children {
                    replacement.children = updateDescendantPaths(
                        in: children,
                        oldPathPrefix: updated[idx].path,
                        newPathPrefix: renamedItem.path,
                        newParentURL: renamedItem.localURL
                    )
                }
                updated[idx] = replacement
                return updated
            }
            if let children = updated[idx].children {
                updated[idx].children = renameNodeInTree(in: children, targetID: targetID, renamedItem: renamedItem)
            }
        }
        return updated
    }

    /// Recursively updates relative paths and local file URLs for all descendants of a renamed directory node.
    func updateDescendantPaths(
        in nodes: [MediaItem],
        oldPathPrefix: String,
        newPathPrefix: String,
        newParentURL: URL?
    ) -> [MediaItem] {
        nodes.map { item in
            let updatedPath: String
            if item.path == oldPathPrefix {
                updatedPath = newPathPrefix
            } else if item.path.hasPrefix(oldPathPrefix + "/") {
                let relativeSuffix = String(item.path.dropFirst(oldPathPrefix.count + 1))
                updatedPath = "\(newPathPrefix)/\(relativeSuffix)"
            } else {
                updatedPath = item.path
            }

            let updatedLocalURL = newParentURL?.appendingPathComponent(item.name, isDirectory: item.isDirectory)
            let updatedChildren: [MediaItem]?
            if let children = item.children {
                updatedChildren = updateDescendantPaths(
                    in: children,
                    oldPathPrefix: oldPathPrefix,
                    newPathPrefix: newPathPrefix,
                    newParentURL: updatedLocalURL
                )
            } else {
                updatedChildren = nil
            }

            return MediaItem(
                locationID: item.locationID,
                name: item.name,
                rootName: item.rootName,
                path: updatedPath,
                isDirectory: item.isDirectory,
                size: item.size,
                modifiedDate: item.modifiedDate,
                children: updatedChildren,
                localURL: updatedLocalURL,
                phAssetIdentifier: item.phAssetIdentifier,
                isMediaVideo: item.isMediaVideo,
                folderIconName: item.folderIconName
            )
        }
    }
    
    // MARK: - Folder Picker Hierarchy
    
    /// Loads the root directory tree for picking destination folders in the move sheet.
    ///
    /// Reuses already loaded subfolder branches from the sidebar tree when available,
    /// or fetches immediate child directories without recursive traversal to minimize latency.
    ///
    /// - Returns: An array containing the root directory with its immediate child folders.
    public func loadFolderPickerTree() async throws -> [MediaItem] {
        guard let location = currentLocation else { return [] }
        switch location.kind {
        case .localFolder, .iCloudFolder:
            guard let rootItem = folderTree.first, rootItem.localURL != nil else {
                return []
            }
            var rootWithChildren = rootItem
            if let existing = rootItem.children {
                rootWithChildren.children = existing
            } else {
                let immediateSubfolders = try await localWorker.listSubfolders(at: rootItem, locationID: rootItem.locationID)
                rootWithChildren.children = immediateSubfolders.isEmpty ? [] : immediateSubfolders
            }
            return [rootWithChildren]
            
        case .smb:
            let activeShareName = selectedFolder?.shareName ?? ""
            guard let rootItem = folderTree.first(where: { $0.shareName == activeShareName }) ?? folderTree.first else {
                return []
            }
            var rootWithChildren = rootItem
            if let existing = rootItem.children {
                rootWithChildren.children = existing
            } else {
                let immediateSubfolders = try await worker.listSubfolders(inShare: rootItem.shareName, atPath: "")
                rootWithChildren.children = immediateSubfolders.isEmpty ? [] : immediateSubfolders
            }
            return [rootWithChildren]
            
        case .photos:
            return []
        }
    }
    
    /// Fetches immediate child subfolders for an individual directory node in the destination folder picker.
    ///
    /// - Parameter folder: The folder node being expanded by the user.
    /// - Returns: Discovered immediate child subfolders.
    public func fetchSubfoldersForPicker(at folder: MediaItem) async throws -> [MediaItem] {
        if folder.localURL != nil {
            return try await localWorker.listSubfolders(at: folder, locationID: folder.locationID)
        } else if folder.locationID == StorageLocation.photosLocationID {
            return []
        } else {
            return try await worker.listSubfolders(inShare: folder.shareName, atPath: folder.path)
        }
    }
}
