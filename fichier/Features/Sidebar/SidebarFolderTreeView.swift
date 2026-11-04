//
//  SidebarFolderTreeView.swift
//  fichier
//

import SwiftUI

struct SidebarFolderTreeView: View {
    var manager: StorageLocationManager
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
        .listStyle(.sidebar)
        .refreshable {
            await manager.refreshSharesAndFolders()
        }
    }
    
    private func isRootInitiallyExpanded(_ root: MediaItem) -> Bool {
        guard let selected = manager.selectedFolder else { return false }
        return selected.shareName == root.shareName || selected.rootName == root.rootName
    }
    
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
