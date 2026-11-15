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
            return try await localWorker.listSubfolders(at: folder, locationID: folder.connectionID)
        } else if folder.locationID == StorageLocation.photosLocationID {
            return []
        } else {
            return try await worker.listSubfolders(inShare: folder.shareName, atPath: folder.path)
        }
    }
}
