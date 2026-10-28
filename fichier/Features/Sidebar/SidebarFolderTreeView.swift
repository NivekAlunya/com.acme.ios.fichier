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
            Section("Server Shares (\(manager.folderTree.count))") {
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
}
