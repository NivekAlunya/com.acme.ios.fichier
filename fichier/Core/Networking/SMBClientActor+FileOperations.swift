//
//  SMBClientActor+FileOperations.swift
//  fichier
//

import Foundation
import UIKit
import FichierKit

extension SMBClientActor {
    // MARK: - File Management Operations

    /// Creates a new subfolder within an SMB share and returns the created `MediaItem`.
    func createFolder(
        named name: String,
        inShare shareName: String,
        atPath parentPath: String
    ) async throws -> MediaItem {
        try Task.checkCancellation()
        guard let client else {
            throw URLError(.notConnectedToInternet)
        }

        let trimmedName = try FileOperationError.validateName(name)
        let cleanParent = parentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let newFolderPath = cleanParent.isEmpty ? trimmedName : "\(cleanParent)/\(trimmedName)"
        let canonicalPath = "/\(newFolderPath)"
        let connID = self.currentConnectionID

        try await client.createDirectory(share: shareName, path: newFolderPath)

        return MediaItem(
            locationID: connID,
            name: trimmedName,
            rootName: shareName,
            path: canonicalPath,
            isDirectory: true,
            size: 0,
            modifiedDate: Date(),
            children: nil,
            localURL: nil
        )
    }

    /// Permanently deletes items (files or subfolders) from the remote SMB share and evicts cached representations.
    func deleteItems(_ items: [MediaItem]) async throws {
        try Task.checkCancellation()
        guard let client else {
            throw URLError(.notConnectedToInternet)
        }
        guard !items.isEmpty else { return }

        // Execute remote removals
        for item in items {
            try Task.checkCancellation()
            try await client.removeItem(share: item.shareName, path: item.smbRelativePath)

            // Evict in-memory and disk caches
            let memoryCacheKey = "\(item.id)_thumb" as NSString
            thumbnailCache.removeObject(forKey: memoryCacheKey)
            fullImageCache.removeObject(forKey: "\(item.id)_full" as NSString)
            metadataCache.removeObject(forKey: item.id as NSString)
        }

        await MediaCacheManager.shared.invalidateThumbnailCache(for: items)
    }

    /// Moves a collection of media items or subfolders to a target destination folder on the same SMB share.
    func moveItems(_ items: [MediaItem], to destinationFolder: MediaItem) async throws {
        try Task.checkCancellation()
        guard let client else {
            throw URLError(.notConnectedToInternet)
        }
        guard !items.isEmpty else { return }

        let destShare = destinationFolder.shareName
        let destPath = destinationFolder.smbRelativePath

        // Pre-flight check: all items must belong to the same connection and share as destination
        for item in items {
            guard item.locationID == destinationFolder.locationID,
                  item.shareName == destShare else {
                throw FileOperationError.unsupportedStorage
            }
        }

        var plannedMoves: [(fromPath: String, toPath: String, item: MediaItem)] = []
        var plannedTargets = Set<String>()

        for item in items {
            let sourcePath = item.smbRelativePath

            // Cannot move directory into itself or descendant
            if item.isDirectory {
                if destPath == sourcePath || destPath.hasPrefix(sourcePath + "/") {
                    throw FileOperationError.cannotMoveIntoSelf
                }
            }

            // Skip if already in destination
            let sourceParent = (sourcePath as NSString).deletingLastPathComponent
            let normalizedParent = (sourceParent == "." ? "" : sourceParent)
            if normalizedParent == destPath {
                continue
            }

            let targetPath = destPath.isEmpty ? item.name : "\(destPath)/\(item.name)"
            if plannedTargets.contains(targetPath) {
                throw FileOperationError.itemAlreadyExists(item.name)
            }
            plannedTargets.insert(targetPath)
            plannedMoves.append((sourcePath, targetPath, item))
        }

        for move in plannedMoves {
            try Task.checkCancellation()
            try await client.moveItem(share: destShare, fromPath: move.fromPath, toPath: move.toPath)

            // Evict in-memory and disk caches
            let memoryCacheKey = "\(move.item.id)_thumb" as NSString
            thumbnailCache.removeObject(forKey: memoryCacheKey)
            fullImageCache.removeObject(forKey: "\(move.item.id)_full" as NSString)
            metadataCache.removeObject(forKey: move.item.id as NSString)
        }

        await MediaCacheManager.shared.invalidateThumbnailCache(for: items)
    }

    /// Renames a file or directory within its parent directory on an SMB share.
    ///
    /// - Parameters:
    ///   - item: The `MediaItem` to rename.
    ///   - newName: The new filename or directory name.
    /// - Returns: The updated `MediaItem`.
    /// - Throws: `FileOperationError` or SMB/network errors.
    func renameItem(_ item: MediaItem, to newName: String) async throws -> MediaItem {
        try Task.checkCancellation()
        guard let client else {
            throw URLError(.notConnectedToInternet)
        }

        let trimmed = try FileOperationError.validateName(newName)

        if trimmed == item.name {
            return item
        }

        let sourcePath = item.smbRelativePath
        let parentPath = (sourcePath as NSString).deletingLastPathComponent
        let normalizedParent = (parentPath == "." ? "" : parentPath)
        let targetPath = normalizedParent.isEmpty ? trimmed : "\(normalizedParent)/\(trimmed)"

        try await client.moveItem(share: item.shareName, fromPath: sourcePath, toPath: targetPath)

        let canonicalTargetPath = targetPath.hasPrefix("/") ? targetPath : "/\(targetPath)"
        let finalPath = item.path.hasPrefix("/") ? canonicalTargetPath : targetPath

        let renamedItem = MediaItem(
            locationID: item.locationID,
            name: trimmed,
            rootName: item.rootName,
            path: finalPath,
            isDirectory: item.isDirectory,
            size: item.size,
            modifiedDate: Date(),
            children: item.children,
            localURL: nil,
            phAssetIdentifier: nil,
            isMediaVideo: item.isMediaVideo,
            folderIconName: item.folderIconName
        )

        // Migrate in-memory thumbnail cache
        let oldMemoryKey = "\(item.id)_thumb" as NSString
        let newMemoryKey = "\(renamedItem.id)_thumb" as NSString
        if let cachedThumb = thumbnailCache.object(forKey: oldMemoryKey) {
            thumbnailCache.setObject(cachedThumb, forKey: newMemoryKey)
            thumbnailCache.removeObject(forKey: oldMemoryKey)
        }
        fullImageCache.removeObject(forKey: "\(item.id)_full" as NSString)
        metadataCache.removeObject(forKey: item.id as NSString)

        // Migrate disk thumbnail cache
        await MediaCacheManager.shared.migrateThumbnailCache(from: item, to: renamedItem)

        return renamedItem
    }

    /// Lists immediate child subfolders in the given directory of an SMB share.
    ///
    /// - Parameters:
    ///   - shareName: Name of the SMB share volume.
    ///   - path: Relative path within the share.
    /// - Returns: Sorted array of immediate child subfolders.
    func listSubfolders(
        inShare shareName: String,
        atPath path: String
    ) async throws -> [MediaItem] {
        let (subfolders, _) = try await scanFolder(shareName: shareName, at: path)
        return subfolders
    }
}
