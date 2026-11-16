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
                            String(localized: .Strings.gallerySectionSubfoldersCount(0)),
                            systemImage: "folder"
                        )
                    } description: {
                        Text(.Strings.galleryNoFolderSelectedDescription)
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
    
    /// Root-level tree nodes displayed in the middle column, scoped to the active share's children for SMB connections.
    private var displayedTreeNodes: [MediaItem] {
        guard manager.currentLocation?.kind == .smb else {
            return manager.folderTree
        }
        guard let activeShare = manager.selectedShare else {
            return []
        }
        let matchedNode = manager.folderTree.first(where: { $0.shareName == activeShare.shareName }) ?? activeShare
        if let children = matchedNode.children {
            return children
        }
        if manager.selectedFolder?.shareName == activeShare.shareName {
            return manager.currentFolders
        }
        return []
    }

    /// Determines whether a root share/folder node should be expanded automatically upon initial appearance.
    ///
    /// - Parameter root: The root `MediaItem` being evaluated.
    /// - Returns: `true` if the currently selected folder belongs to this root tree.
    private func isRootInitiallyExpanded(_ root: MediaItem) -> Bool {
        guard let selected = manager.selectedFolder else { return false }
        if manager.currentLocation?.kind == .smb {
            return selected.path.hasPrefix(root.path) && selected.path != root.path
        }
        return selected.shareName == root.shareName || selected.rootName == root.rootName
    }
    
    /// Localized title for the folder tree section header based on active storage kind.
    private var sectionHeaderTitle: String {
        if manager.currentLocation?.kind == .photos {
            return String(localized: .Strings.sidebarLocationPhotos)
        }
        if manager.currentLocation?.kind == .localFolder || manager.currentLocation?.kind == .iCloudFolder {
            return String(localized: .Strings.gallerySectionSubfoldersCount(manager.folderTree.count))
        }
        return String(localized: .Strings.gallerySectionSubfoldersCount(displayedTreeNodes.count))
    }
}
