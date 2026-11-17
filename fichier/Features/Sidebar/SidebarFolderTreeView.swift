//
//  SidebarFolderTreeView.swift
//  fichier
//

import SwiftUI

/// Sidebar view that renders the root-level collection of shares and folders for the current storage location.
///
/// Iterates over `manager.folderTree`, constructing hierarchical `FolderTreeNodeView` instances
/// that support lazy folder expansion and automatic initial expansion matching the selected item.
struct SidebarFolderTreeView: View {
    /// Centralized storage location manager.
    var manager: StorageLocationManager
    
    /// Optional callback to reveal or navigate back to the sidebar programmatically.
    var onOpenSidebar: (() -> Void)? = nil

    /// Callback triggered when a folder node is selected by the user.
    let onSelectFolder: (MediaItem) -> Void
    
    var body: some View {
        Group {
            if displayedTreeNodes.isEmpty {
                if manager.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(.Strings.sidebarLoadingShares)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label(
                            String(localized: .Strings.folders),
                            systemImage: "folder"
                        )
                    } description: {
                        VStack(spacing: 8) {
                            Text(.Strings.selectStorageDescription)
                            HStack(spacing: 5) {
                                Image(systemName: "sidebar.leading")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tint)
                                Text(.Strings.selectStorageSidebarInstruction)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                List {
                    Section(sectionHeaderTitle) {
                        ForEach(displayedTreeNodes) { childNode in
                            FolderTreeNodeView(
                                node: childNode,
                                level: 0,
                                isInitiallyExpanded: isRootInitiallyExpanded(childNode),
                                manager: manager,
                                onSelectFolder: onSelectFolder
                            )
                        }
                    }
                }
                #if os(tvOS)
                .listStyle(.plain)
                #else
                .listStyle(.sidebar)
                #endif
                .refreshable {
                    await manager.refreshSharesAndFolders()
                }
            }
        }
        .onChange(of: manager.navigationCoordinator.mutationRevision) { _, _ in
            Task {
                await manager.refreshExpandedTreeBranches()
            }
        }
    }
    
    /// Root-level tree nodes displayed in the middle column, starting with the root folder/share.
    private var displayedTreeNodes: [MediaItem] {
        guard manager.currentLocation?.kind == .smb else {
            return manager.folderTree
        }
        guard let activeShare = manager.selectedShare else {
            return []
        }
        var matchedNode = manager.folderTree.first(where: { $0.shareName == activeShare.shareName }) ?? activeShare
        if matchedNode.children == nil && manager.selectedFolder?.shareName == activeShare.shareName && manager.selectedFolder?.path.isEmpty == true && !manager.currentFolders.isEmpty {
            matchedNode.children = manager.currentFolders
        }
        return [matchedNode]
    }

    /// Determines whether a root share/folder node should be expanded automatically upon initial appearance.
    ///
    /// - Parameter root: The root `MediaItem` being evaluated.
    /// - Returns: `true` if the currently selected folder belongs to this root tree.
    private func isRootInitiallyExpanded(_ root: MediaItem) -> Bool {
        guard let selected = manager.selectedFolder else {
            return manager.selectedShare?.shareName == root.shareName
        }
        return selected.shareName == root.shareName || selected.rootName == root.rootName
    }
    
    /// Title for the folder tree section header displaying folder and file counts.
    private var sectionHeaderTitle: String {
        let folderCount = manager.selectedFolder != nil ? manager.currentFolders.count : displayedTreeNodes.count
        let fileCount = manager.pictures.count
        return "Folder \(folderCount) File \(fileCount)"
    }
}
