//
//  FolderTreeNodeView.swift
//  fichier
//

import SwiftUI

/// Recursive tree row that supports both expanding subfolders and selecting the folder to display its media
struct FolderTreeNodeView: View {
    let node: SMBItem
    let level: Int
    @State private var isExpanded: Bool
    var manager: SMBDirectManager
    let onSelectFolder: (SMBItem) -> Void
    
    init(
        node: SMBItem,
        level: Int,
        isInitiallyExpanded: Bool = false,
        manager: SMBDirectManager,
        onSelectFolder: @escaping (SMBItem) -> Void
    ) {
        self.node = node
        self.level = level
        self._isExpanded = State(initialValue: isInitiallyExpanded)
        self.manager = manager
        self.onSelectFolder = onSelectFolder
    }
    
    private var isSelected: Bool {
        manager.selectedFolder?.id == node.id
    }
    
    var body: some View {
        HStack(spacing: 6) {
            if level > 0 {
                Spacer()
                    .frame(width: CGFloat(level) * 16)
            }
            
            // Expand / Collapse chevron button
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
                if isExpanded && node.children == nil {
                    Task {
                        await manager.loadSubfoldersForTree(at: node)
                    }
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Folder selection button (loads media & navigates to detail view)
            Button {
                isExpanded = true
                onSelectFolder(node)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: level == 0 ? "externaldrive.fill.badge.wifi" : (isSelected ? "folder.fill" : "folder"))
                        .foregroundColor(isSelected ? .blue : .accentColor)
                    
                    Text(node.name)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if isSelected && manager.isLoading {
                        ProgressView()
                            .scaleEffect(0.75)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(isSelected ? Color.blue.opacity(0.14) : Color.clear)
        
        // Render child subfolders recursively when expanded
        if isExpanded, let children = node.children {
            ForEach(children) { child in
                FolderTreeNodeView(
                    node: child,
                    level: level + 1,
                    isInitiallyExpanded: false,
                    manager: manager,
                    onSelectFolder: onSelectFolder
                )
            }
        }
    }
}
