//
//  SidebarFolderTreeView.swift
//  fichier
//

import SwiftUI

struct SidebarFolderTreeView: View {
    var manager: SMBDirectManager
    let onSelectFolder: (SMBItem) -> Void
    
    var body: some View {
        List {
            Section(sectionHeaderTitle) {
                ForEach(manager.folderTree) { shareRootNode in
                    FolderTreeNodeView(
                        node: shareRootNode,
                        level: 0,
                        isInitiallyExpanded: manager.selectedFolder?.shareName == shareRootNode.shareName,
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
    
    private var sectionHeaderTitle: String {
        if let remote = manager.savedConnections.first(where: { manager.currentConnectionID == $0.id }) {
            return "\(remote.displayName) (\(manager.folderTree.count))"
        }
        return String(localized: .Strings.sidebarSectionServerShares(manager.folderTree.count))
    }
}
