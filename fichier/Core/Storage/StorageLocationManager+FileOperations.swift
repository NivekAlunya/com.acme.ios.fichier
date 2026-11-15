//
//  StorageLocationManager+FileOperations.swift
//  fichier
//

import Foundation
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
    /// - Throws: `FileOperationError` if the name is invalid, already exists, or the backend is unsupported.
    public func createFolder(named name: String, in targetFolder: MediaItem? = nil) async throws {
        guard let current = targetFolder ?? selectedFolder else {
            throw FileOperationError.unsupportedStorage
        }
        
        if current.localURL != nil {
            _ = try await localWorker.createFolder(
                named: name,
                in: current,
                locationID: current.locationID
            )
        } else if !current.shareName.isEmpty {
            _ = try await worker.createFolder(
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
        
        recordMutation()
        await refreshExpandedTreeBranches()
        
        if let current = selectedFolder {
            await selectAndLoadFolder(current)
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
        
        recordMutation()
        await refreshExpandedTreeBranches()
        
        if let current = selectedFolder {
            await selectAndLoadFolder(current)
        }
    }
    
    // MARK: - Folder Picker Hierarchy
    
    /// Loads a complete directory tree for picking destination folders in the move sheet.
    ///
    /// - Returns: An array containing the root directory with populated subfolder children.
    public func loadFolderPickerTree() async throws -> [MediaItem] {
        guard let location = currentLocation else { return [] }
        switch location.kind {
        case .localFolder, .iCloudFolder:
            guard let rootItem = folderTree.first, rootItem.localURL != nil else {
                return []
            }
            var rootWithChildren = rootItem
            rootWithChildren.children = try await localWorker.listSubfoldersRecursively(
                at: rootItem,
                locationID: rootItem.locationID
            )
            return [rootWithChildren]
            
        case .smb:
            let activeShareName = selectedFolder?.shareName ?? ""
            guard let rootItem = folderTree.first(where: { $0.shareName == activeShareName }) ?? folderTree.first else {
                return []
            }
            var rootWithChildren = rootItem
            rootWithChildren.children = try await worker.listSubfoldersRecursively(
                inShare: rootItem.shareName,
                atPath: "",
                rootName: rootItem.rootName,
                locationID: rootItem.locationID
            )
            return [rootWithChildren]
            
        case .photos:
            return []
        }
    }
}
