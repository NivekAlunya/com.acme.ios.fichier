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
        case .smb, .photos:
            return false
        }
    }
    
    /// Checks whether an individual media item supports filesystem manipulation.
    ///
    /// - Parameter item: The item to inspect.
    /// - Returns: `true` if the item resides on local or iCloud storage and has a local URL.
    public func canManageItem(_ item: MediaItem) -> Bool {
        guard let location = currentLocation else { return false }
        switch location.kind {
        case .localFolder, .iCloudFolder:
            return item.localURL != nil
        case .smb, .photos:
            return false
        }
    }
    
    // MARK: - Folder Creation
    
    /// Creates a new subfolder in the currently selected directory and refreshes folder contents.
    ///
    /// - Parameter name: The name of the new directory to create.
    /// - Throws: `FileOperationError` if the name is invalid, already exists, or the backend is unsupported.
    public func createFolder(named name: String) async throws {
        guard let current = selectedFolder, current.localURL != nil else {
            throw FileOperationError.unsupportedStorage
        }
        
        _ = try await localWorker.createFolder(
            named: name,
            in: current,
            locationID: current.locationID
        )
        
        await selectAndLoadFolder(current)
    }
    
    // MARK: - Deletion / Move to Trash
    
    /// Moves a collection of items (files or subfolders) to the system Trash.
    ///
    /// - Parameter items: The items to delete.
    /// - Throws: `FileOperationError` if deletion fails or storage is unsupported.
    public func deleteItems(_ items: [MediaItem]) async throws {
        guard !items.isEmpty else { return }
        guard items.allSatisfy({ $0.localURL != nil }) else {
            throw FileOperationError.unsupportedStorage
        }
        
        try await localWorker.deleteItems(items)
        
        for item in items where FavoritesManager.shared.isFavorite(item) {
            FavoritesManager.shared.toggleFavorite(item)
        }
        
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
    /// - Throws: `FileOperationError` if moving fails.
    public func moveItems(_ items: [MediaItem], to destinationFolder: MediaItem) async throws {
        guard !items.isEmpty else { return }
        guard items.allSatisfy({ $0.localURL != nil }), destinationFolder.localURL != nil else {
            throw FileOperationError.unsupportedStorage
        }
        
        try await localWorker.moveItems(items, to: destinationFolder)
        
        if let current = selectedFolder {
            await selectAndLoadFolder(current)
        }
    }
    
    // MARK: - Folder Picker Hierarchy
    
    /// Loads a complete directory tree for picking destination folders in the move sheet.
    ///
    /// - Returns: An array containing the root directory with populated subfolder children.
    public func loadFolderPickerTree() async throws -> [MediaItem] {
        guard let rootItem = folderTree.first, rootItem.localURL != nil else {
            return []
        }
        
        var rootWithChildren = rootItem
        rootWithChildren.children = try await localWorker.listSubfoldersRecursively(
            at: rootItem,
            locationID: rootItem.locationID
        )
        return [rootWithChildren]
    }
}
