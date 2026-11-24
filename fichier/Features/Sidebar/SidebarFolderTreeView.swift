//
//  SidebarFolderTreeView.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Sidebar section that renders the hierarchical folder tree for the currently selected storage drive or SMB share.
///
/// Designed to be embedded inside `LocationsSidebarView`'s `List`.
/// Handles loading, empty-shares, and populated tree states using `FolderTreeNodeView`
/// with lazy folder expansion and automatic initial expansion matching the selected item.
struct SidebarFolderTreeView: View {
    /// Centralized storage location manager.
    var manager: StorageLocationManager

    /// Callback triggered when a folder node is selected by the user.
    let onSelectFolder: (MediaItem) -> Void
    
    var body: some View {
        Section {
            if displayedTreeNodes.isEmpty {
                if manager.isLoading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(.Strings.sidebarLoadingShares)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(.Strings.networkingErrorNoSharedFolders)
                            .font(.subheadline.weight(.semibold))
                        Text(.Strings.sidebarNoSharesDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            Task {
                                await manager.refreshSharesAndFolders()
                            }
                        } label: {
                            Text(.Strings.connectionButtonRefresh)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }
            } else {
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
        } header: {
            Text(sectionHeaderTitle)
        }
        .onChange(of: manager.navigationCoordinator.mutationRevision) { _, _ in
            Task {
                if manager.folderTree.isEmpty {
                    await manager.refreshSharesAndFolders()
                } else {
                    await manager.refreshExpandedTreeBranches()
                }
            }
        }
    }
    
    /// Root-level tree nodes displayed in the sidebar, starting with the root folder/share.
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
    
    /// Section header reflecting the active drive or SMB share name.
    private var sectionHeaderTitle: String {
        let driveName: String = {
            if manager.currentLocation?.kind == .smb {
                return manager.selectedShare?.name ?? manager.currentLocation?.name ?? ""
            }
            if let location = manager.currentLocation {
                return location.name
            }
            if let remote = manager.savedConnections.first(where: { manager.currentConnectionID == $0.id }) {
                return remote.displayName
            }
            return ""
        }()
        
        guard !driveName.isEmpty else {
            return String(localized: .Strings.folders)
        }
        return driveName
    }
}
