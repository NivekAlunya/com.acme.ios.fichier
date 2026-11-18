//
//  FolderPickerSheetView.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Modal sheet presenting an in-app folder hierarchy for selecting a destination folder.
struct FolderPickerSheetView: View {
    /// Injected storage location manager.
    let manager: StorageLocationManager
    
    /// The media items or folders pending move.
    let itemsToMove: [MediaItem]
    
    /// Callback invoked when a destination folder is confirmed.
    let onMoveTo: (MediaItem) -> Void
    
    /// Callback to dismiss the picker without moving.
    let onDismiss: () -> Void
    
    // MARK: - State Properties
    
    /// Hierarchical tree of available folders.
    @State private var folderTree: [MediaItem] = []
    
    /// Currently highlighted destination folder.
    @State private var selectedDestination: MediaItem?
    
    /// Set of expanded folder IDs in the tree.
    @State private var expandedIDs: Set<String> = []
    
    /// Set of folder IDs currently loading their subfolders on demand.
    @State private var loadingNodeIDs: Set<String> = []
    
    /// Loading state while scanning the initial directory tree.
    @State private var isLoading = true
    
    /// Tracks presentation of the create folder alert.
    @State private var isShowingNewFolderAlert = false
    
    /// Name for a newly created folder inside the picker.
    @State private var newFolderName = ""
    
    /// User-presentable error message if an operation fails.
    @State private var errorMessage: String?
    
    // MARK: - Computed Properties
    
    /// Title indicating number of items being moved.
    private var navigationTitle: String {
        if itemsToMove.count == 1, let first = itemsToMove.first {
            return String(localized: .Strings.galleryMoveSingleItemTitle(first.name))
        }
        return String(localized: .Strings.galleryMoveMultipleItemsTitle(itemsToMove.count))
    }
    
    /// Validates whether a given folder can accept the items to move.
    private func isDestinationValid(_ folder: MediaItem) -> Bool {
        guard !itemsToMove.isEmpty else { return false }
        
        // Ensure destination matches storage type and share boundary
        if folder.localURL != nil {
            guard itemsToMove.allSatisfy({ $0.localURL != nil }) else { return false }
        } else if !folder.shareName.isEmpty {
            guard itemsToMove.allSatisfy({
                $0.localURL == nil && $0.shareName == folder.shareName && $0.locationID == folder.locationID
            }) else {
                return false
            }
        } else {
            return false
        }
        
        // 1. Cannot move directly onto an item that is being moved
        if itemsToMove.contains(where: { $0.id == folder.id }) {
            return false
        }
        
        // 2. If moving directories, cannot move into self or any descendant
        for movingItem in itemsToMove where movingItem.isDirectory {
            if let movingURL = movingItem.localURL, let folderURL = folder.localURL {
                let movingPath = movingURL.standardizedFileURL.path
                let standardizedFolderPath = folderURL.standardizedFileURL.path
                if standardizedFolderPath == movingPath || standardizedFolderPath.hasPrefix(movingPath + "/") {
                    return false
                }
            } else if movingItem.shareName == folder.shareName && movingItem.locationID == folder.locationID {
                let movingPath = movingItem.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let folderPath = folder.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if folderPath == movingPath || folderPath.hasPrefix(movingPath + "/") {
                    return false
                }
            }
        }
        
        // 3. Cannot move if all items are already located in this folder
        let allAlreadyInDestination = itemsToMove.allSatisfy { item in
            if let itemURL = item.localURL, let folderURL = folder.localURL {
                return itemURL.deletingLastPathComponent().standardizedFileURL.path == folderURL.standardizedFileURL.path
            } else if item.shareName == folder.shareName && item.locationID == folder.locationID {
                let itemParent = (item.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) as NSString).deletingLastPathComponent
                let normalizedParent = (itemParent == "." ? "" : itemParent)
                let normalizedFolder = folder.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return normalizedParent == normalizedFolder
            }
            return false
        }
        if allAlreadyInDestination {
            return false
        }
        
        return true
    }
    
    /// Flattens the visible tree nodes based on current expansion state.
    private func visibleNodes(from items: [MediaItem], level: Int = 0) -> [(folder: MediaItem, level: Int)] {
        var result: [(folder: MediaItem, level: Int)] = []
        for item in items {
            result.append((folder: item, level: level))
            if expandedIDs.contains(item.id), let children = item.children {
                result.append(contentsOf: visibleNodes(from: children, level: level + 1))
            }
        }
        return result
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(.Strings.galleryLoadingFolders)
                } else if folderTree.isEmpty {
                    ContentUnavailableView(
                        label: {
                            Label(.Strings.galleryNoFoldersAvailableTitle, systemImage: "folder.badge.questionmark")
                        },
                        description: {
                            Text(.Strings.galleryNoFoldersAvailableDescription)
                        }
                    )
                } else {
                    List {
                        let nodes = visibleNodes(from: folderTree)
                        ForEach(nodes, id: \.folder.id) { node in
                            FolderPickerRowView(
                                folder: node.folder,
                                level: node.level,
                                isSelected: selectedDestination?.id == node.folder.id,
                                isExpanded: expandedIDs.contains(node.folder.id),
                                isEnabled: isDestinationValid(node.folder),
                                isLoading: loadingNodeIDs.contains(node.folder.id),
                                onToggleExpand: {
                                    toggleExpand(for: node.folder)
                                },
                                onSelect: {
                                    selectedDestination = node.folder
                                    if !expandedIDs.contains(node.folder.id) {
                                        toggleExpand(for: node.folder)
                                    }
                                }
                            )
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.Strings.commonCancel) {
                        onDismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        newFolderName = ""
                        isShowingNewFolderAlert = true
                    } label: {
                        Label(.Strings.commonNewFolder, systemImage: "folder.badge.plus")
                    }
                    .disabled(isLoading || selectedDestination == nil)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(.Strings.galleryActionMoveHere) {
                        if let destination = selectedDestination {
                            onMoveTo(destination)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedDestination.map(isDestinationValid) != true)
                }
            }
            .alert(
                .Strings.commonNewFolder,
                isPresented: $isShowingNewFolderAlert
            ) {
                TextField(String(localized: .Strings.commonFolderName), text: $newFolderName)
                Button(.Strings.commonCancel, role: .cancel) {}
                Button(.Strings.commonCreate) {
                    createNewFolder()
                }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                if let target = selectedDestination {
                    Text(.Strings.galleryCreateSubfolderPrompt(target.name.isEmpty ? target.rootName : target.name))
                }
            }
            .alert(
                .Strings.galleryErrorUnableToCreateFolder,
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(.Strings.commonOk, role: .cancel) {}
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
            .task {
                await loadTree()
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadTree() async {
        isLoading = true
        do {
            let tree = try await manager.loadFolderPickerTree()
            folderTree = tree
            if let root = tree.first {
                expandedIDs.insert(root.id)
                // Default selection to root if valid
                if isDestinationValid(root) {
                    selectedDestination = root
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    /// Toggles folder expansion state, lazily loading its child subfolders on demand if not yet cached.
    private func toggleExpand(for folder: MediaItem) {
        if expandedIDs.contains(folder.id) {
            _ = withAnimation(.snappy) {
                expandedIDs.remove(folder.id)
            }
        } else {
            if let children = folder.children {
                if !children.isEmpty {
                    _ = withAnimation(.snappy) {
                        expandedIDs.insert(folder.id)
                    }
                }
                return
            }
            
            loadingNodeIDs.insert(folder.id)
            Task {
                do {
                    let subfolders = try await manager.fetchSubfoldersForPicker(at: folder)
                    folderTree = manager.updateSubfoldersInTree(in: folderTree, targetID: folder.id, children: subfolders)
                    if !subfolders.isEmpty {
                        _ = withAnimation(.snappy) {
                            expandedIDs.insert(folder.id)
                        }
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
                loadingNodeIDs.remove(folder.id)
            }
        }
    }
    
    private func createNewFolder() {
        guard let parent = selectedDestination else { return }
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        Task {
            do {
                let created = try await manager.createFolder(named: trimmed, in: parent)
                let subfolders = try await manager.fetchSubfoldersForPicker(at: parent)
                folderTree = manager.updateSubfoldersInTree(in: folderTree, targetID: parent.id, children: subfolders)
                _ = withAnimation(.snappy) {
                    expandedIDs.insert(parent.id)
                }
                selectedDestination = created
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
