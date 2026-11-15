//
//  FolderPickerSheetView.swift
//  fichier
//

import SwiftUI

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
    
    /// Loading state while scanning the directory tree.
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
            return String(localized: "Move '\(first.name)'", comment: "Title when moving a single item")
        }
        return String(localized: "Move \(itemsToMove.count) Items", comment: "Title when moving multiple items")
    }
    
    /// Validates whether a given folder can accept the items to move.
    private func isDestinationValid(_ folder: MediaItem) -> Bool {
        guard let folderURL = folder.localURL else { return false }
        let standardizedFolderPath = folderURL.standardizedFileURL.path
        
        // 1. Cannot move directly onto an item that is being moved
        if itemsToMove.contains(where: { $0.id == folder.id }) {
            return false
        }
        
        // 2. If moving directories, cannot move into self or any descendant
        for movingItem in itemsToMove where movingItem.isDirectory {
            if let movingURL = movingItem.localURL {
                let movingPath = movingURL.standardizedFileURL.path
                if standardizedFolderPath == movingPath || standardizedFolderPath.hasPrefix(movingPath + "/") {
                    return false
                }
            }
        }
        
        // 3. Cannot move if all items are already located in this folder
        let allAlreadyInDestination = itemsToMove.allSatisfy { item in
            guard let itemURL = item.localURL else { return false }
            return itemURL.deletingLastPathComponent().standardizedFileURL.path == standardizedFolderPath
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
                    ProgressView(String(localized: "Loading folders...", comment: "Progress text while loading folder hierarchy"))
                } else if folderTree.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Folders Available", comment: "Empty state title when no folders found"),
                        systemImage: "folder.badge.questionmark",
                        description: Text(String(localized: "No destination folders could be located.", comment: "Empty state description"))
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
                                onToggleExpand: {
                                    withAnimation(.snappy) {
                                        if expandedIDs.contains(node.folder.id) {
                                            expandedIDs.remove(node.folder.id)
                                        } else {
                                            expandedIDs.insert(node.folder.id)
                                        }
                                    }
                                },
                                onSelect: {
                                    selectedDestination = node.folder
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
                    Button(String(localized: "Cancel", comment: "Cancel button")) {
                        onDismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        newFolderName = ""
                        isShowingNewFolderAlert = true
                    } label: {
                        Label(String(localized: "New Folder", comment: "New folder button"), systemImage: "folder.badge.plus")
                    }
                    .disabled(isLoading || selectedDestination == nil)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Move Here", comment: "Move here confirmation button")) {
                        if let destination = selectedDestination {
                            onMoveTo(destination)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedDestination.map(isDestinationValid) != true)
                }
            }
            .alert(
                String(localized: "New Folder", comment: "Alert title for creating new folder"),
                isPresented: $isShowingNewFolderAlert
            ) {
                TextField(String(localized: "Folder Name", comment: "Placeholder for new folder name"), text: $newFolderName)
                Button(String(localized: "Cancel", comment: "Cancel button"), role: .cancel) {}
                Button(String(localized: "Create", comment: "Create button")) {
                    createNewFolder()
                }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                if let target = selectedDestination {
                    Text(String(localized: "Create a subfolder inside '\(target.name.isEmpty ? target.rootName : target.name)'.", comment: "Prompt explaining where folder will be created"))
                }
            }
            .alert(
                String(localized: "Unable to Create Folder", comment: "Error alert title"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(String(localized: "OK", comment: "Dismiss error alert button"), role: .cancel) {}
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
    
    private func createNewFolder() {
        guard let parent = selectedDestination else { return }
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        Task {
            do {
                _ = try await manager.localWorker.createFolder(
                    named: trimmed,
                    in: parent,
                    locationID: parent.locationID
                )
                await loadTree()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
