//
//  StorageLocationManager+FolderLoading.swift
//  fichier
//

import Foundation
import Wappn
import FichierKit

@MainActor
extension StorageLocationManager {
    // MARK: - Select Share

    /// Selects an SMB share as the active source and loads its contents.
    ///
    /// - Parameter share: The target SMB share to browse.
    public func selectShare(_ share: MediaItem) async {
        self.selectedShare = share
        await selectAndLoadFolder(share)
    }

    // MARK: - Select Folder & Load Both Subfolders + Pictures

    /// Selects a folder item and asynchronously enumerates its child subfolders and media files.
    ///
    /// ### Concurrency and Invalidation Strategy
    /// 1. Advances `folderGeneration` and cancels any ongoing `loadFolderTask` to prioritize the new user action.
    /// 2. Clears the existing `pictures` and `currentFolders` collections to cause obsolete UI
    ///    cells to unmount and drop their active thumbnail generation tasks.
    /// 3. Signals the `worker` actor with the new `activeFolderID` to discard queued thumbnail requests.
    /// 4. Checks cooperative task cancellation and `folderGeneration` before committing state.
    ///
    /// - Parameter folder: The folder item to browse.
    public func selectAndLoadFolder(_ folder: MediaItem) async {
        // Record this folder as the last active selection for the current location
        if let locID = currentLocation?.id, !locID.isEmpty {
            lastSelectedFolderPerLocation[locID] = folder
        }

        if currentLocation?.kind == .smb {
            if selectedShare == nil || selectedShare?.shareName != folder.shareName {
                let matchingShare = folderTree.first(where: { $0.shareName == folder.shareName })
                if let matchingShare {
                    selectedShare = matchingShare
                } else if folder.path.isEmpty {
                    selectedShare = folder
                } else if !folder.shareName.isEmpty {
                    selectedShare = MediaItem(
                        locationID: folder.locationID,
                        name: folder.shareName,
                        rootName: folder.shareName,
                        path: "",
                        isDirectory: true
                    )
                }
            }
        }

        // 1. Advance generation and cancel any ongoing folder scan task immediately
        folderGeneration &+= 1
        let expectedGeneration = folderGeneration
        loadFolderTask?.cancel()
        loadFolderTask = nil

        // 2. Set newly selected folder and record active folder ID
        selectedFolder = folder
        activeFolderID = folder.id
        isLoading = true
        errorMessage = nil

        // 3. Immediately clear out previous items so thumbnail views unmount
        // and cancel their ongoing thumbnail tasks in SwiftUI
        pictures = []
        currentFolders = []

        // 4. Notify worker actor of active folder change to immediately invalidate pending thumbnails
        await worker.setActiveFolder(id: folder.id)

        // 5. Spawn cancellable task and await its completion
        let targetID = folder.id
        guard !Task.isCancelled,
              self.folderGeneration == expectedGeneration,
              self.activeFolderID == targetID else {
            if self.folderGeneration == expectedGeneration, self.activeFolderID == targetID {
                self.isLoading = false
            }
            return
        }

        let targetShare = folder.shareName
        let targetPath = folder.path
        let targetName = folder.name
        let isLocal = folder.localURL != nil
        let isPhotos = folder.locationID == StorageLocation.photosLocationID

        let task = Task { [weak self, worker, localWorker, photosWorker] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let subfolders: [MediaItem]
                let foundPictures: [MediaItem]

                if isLocal {
                    let (subs, media) = try await localWorker.listContents(at: folder, locationID: folder.connectionID)
                    subfolders = subs
                    foundPictures = media
                } else if isPhotos {
                    let (subs, media) = try await photosWorker.listContents(at: folder)
                    subfolders = subs
                    foundPictures = media
                } else {
                    let (subs, media) = try await worker.scanFolder(shareName: targetShare, at: targetPath)
                    subfolders = subs
                    foundPictures = media
                }

                try Task.checkCancellation()

                guard !Task.isCancelled,
                      self.folderGeneration == expectedGeneration,
                      self.activeFolderID == targetID else {
                    return
                }

                self.currentFolders = subfolders
                self.pictures = foundPictures
                self.folderTree = self.updateTreeNodes(in: self.folderTree, targetID: targetID, children: subfolders)
                self.isLoading = false
                logi("Folder '\(targetShare)' path '\(targetPath)': \(subfolders.count) subfolders, \(foundPictures.count) items")
            } catch is CancellationError {
                // Clean up loading flag only if this folder was not superseded by a newer selection
                if self.folderGeneration == expectedGeneration, self.activeFolderID == targetID {
                    self.isLoading = false
                }
            } catch {
                guard !Task.isCancelled,
                      self.folderGeneration == expectedGeneration,
                      self.activeFolderID == targetID else {
                    return
                }
                self.errorMessage = String(localized: .Strings.networkingErrorLoadFolderFailed(targetName, error.localizedDescription))
                self.isLoading = false
                loge("Error scanning folder \(targetShare)/\(targetPath): \(error.localizedDescription)")
            }
        }

        loadFolderTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if self.folderGeneration == expectedGeneration {
            self.loadFolderTask = nil
        }
    }

    /// Lazily populates child subfolders in the sidebar tree without altering the active grid selection.
    ///
    /// - Parameter folder: The folder node being expanded in the sidebar.
    public func loadSubfoldersForTree(at folder: MediaItem) async {
        do {
            let subfolders: [MediaItem]
            if folder.localURL != nil {
                let (subs, _) = try await localWorker.listContents(at: folder, locationID: folder.connectionID)
                subfolders = subs
            } else if folder.locationID == StorageLocation.photosLocationID {
                let (subs, _) = try await photosWorker.listContents(at: folder)
                subfolders = subs
            } else {
                let (subs, _) = try await worker.scanFolder(shareName: folder.shareName, at: folder.path)
                subfolders = subs
            }
            self.folderTree = updateTreeNodes(in: self.folderTree, targetID: folder.id, children: subfolders)
        } catch {
            loge("Failed to expand tree at \(folder.shareName)/\(folder.path): \(error.localizedDescription)")
        }
    }

    /// Refreshes all currently expanded branches in the folder tree hierarchy without collapsing nodes.
    public func refreshExpandedTreeBranches() async {
        let expandedNodes = collectNodesWithChildren(in: folderTree)
        for node in expandedNodes {
            await loadSubfoldersForTree(at: node)
        }
    }

    /// Recursively collects all folder nodes within the tree that currently maintain loaded child subfolders.
    private func collectNodesWithChildren(in nodes: [MediaItem]) -> [MediaItem] {
        nodes.flatMap { node -> [MediaItem] in
            guard let children = node.children else { return [] }
            return [node] + (children.isEmpty ? [] : collectNodesWithChildren(in: children))
        }
    }

    /// Pure functional recursive tree traversal that injects loaded child nodes into the corresponding parent.
    ///
    /// Preserves existing loaded sub-children of descendants so deeper expanded branches are not discarded.
    ///
    /// - Parameters:
    ///   - nodes: The current subtree list.
    ///   - targetID: The identifier of the parent node to receive children.
    ///   - children: The discovered child subfolders.
    /// - Returns: A newly constructed tree reflecting the updated child hierarchy.
    func updateTreeNodes(in nodes: [MediaItem], targetID: String, children: [MediaItem]) -> [MediaItem] {
        nodes.map { node in
            var updated = node
            if node.id == targetID {
                let existingChildrenMap = Dictionary(
                    (node.children ?? []).compactMap { child in
                        child.children.map { (child.id, $0) }
                    },
                    uniquingKeysWith: { first, _ in first }
                )
                let mergedChildren = children.map { child -> MediaItem in
                    var updatedChild = child
                    if let existingDescendants = existingChildrenMap[child.id] {
                        updatedChild.children = existingDescendants
                    }
                    return updatedChild
                }
                updated.children = mergedChildren
            } else if let existingChildren = node.children {
                updated.children = updateTreeNodes(in: existingChildren, targetID: targetID, children: children)
            }
            return updated
        }
    }

    /// Updates the child subfolders of a specific node within an in-memory tree hierarchy.
    ///
    /// - Parameters:
    ///   - nodes: Current folder tree.
    ///   - targetID: Identifier of the parent folder being populated.
    ///   - children: The discovered subfolders.
    /// - Returns: A new tree with updated children.
    public func updateSubfoldersInTree(in nodes: [MediaItem], targetID: String, children: [MediaItem]) -> [MediaItem] {
        updateTreeNodes(in: nodes, targetID: targetID, children: children)
    }

    /// Pure functional recursive tree traversal that removes nodes matching the target identifiers.
    ///
    /// - Parameters:
    ///   - nodes: Current folder subtree.
    ///   - targetIDs: Set of identifiers for folder nodes to remove.
    /// - Returns: Updated tree without the target nodes.
    public func removeNodesFromTree(in nodes: [MediaItem], targetIDs: Set<String>) -> [MediaItem] {
        nodes.compactMap { node in
            if targetIDs.contains(node.id) {
                return nil
            }
            var updated = node
            if let children = node.children {
                updated.children = removeNodesFromTree(in: children, targetIDs: targetIDs)
            }
            return updated
        }
    }

    // MARK: - Parent Folder Navigation

    /// Determines whether a folder represents the top-level root of its storage backend.
    ///
    /// - Parameter item: The media item folder to inspect.
    /// - Returns: `true` if the folder cannot be navigated above; `false` otherwise.
    public func isRootFolder(_ item: MediaItem) -> Bool {
        navigationCoordinator.isRootFolder(item)
    }

    /// Recomputes and caches the parent folder of the currently selected folder.
    public func updateParentFolder() {
        parentFolder = navigationCoordinator.resolveParentFolder(for: selectedFolder, in: folderTree)
    }

    /// Recursively searches the expanded tree hierarchy to locate the immediate parent of a target node.
    ///
    /// - Parameters:
    ///   - target: The child item whose parent is sought.
    ///   - nodes: The tree nodes to search.
    /// - Returns: The parent `MediaItem` if discovered in the tree, or `nil`.
    public func findParentInTree(for target: MediaItem, in nodes: [MediaItem]) -> MediaItem? {
        navigationCoordinator.findParentInTree(for: target, in: nodes)
    }

    /// Synthesizes a parent `MediaItem` using path-based string surgery when tree metadata is unavailable.
    ///
    /// - Parameter item: The child folder item.
    /// - Returns: The derived parent `MediaItem`, or `nil` if already at root.
    public func deriveParentFolder(for item: MediaItem) -> MediaItem? {
        navigationCoordinator.deriveParentFolder(for: item, in: folderTree)
    }
}
