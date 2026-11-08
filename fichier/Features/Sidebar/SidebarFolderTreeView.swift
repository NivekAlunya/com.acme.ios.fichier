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
        List {
            Section(sectionHeaderTitle) {
                ForEach(manager.folderTree) { shareRootNode in
                    FolderTreeNodeView(
                        node: shareRootNode,
                        level: 0,
                        isInitiallyExpanded: isRootInitiallyExpanded(shareRootNode),
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
    
    /// Determines whether a root share/folder node should be expanded automatically upon initial appearance.
    ///
    /// - Parameter root: The root `MediaItem` being evaluated.
    /// - Returns: `true` if the currently selected folder belongs to this root tree.
    private func isRootInitiallyExpanded(_ root: MediaItem) -> Bool {
        guard let selected = manager.selectedFolder else { return false }
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
        return String(localized: .Strings.sidebarSectionServerShares(manager.folderTree.count))
    }
}
