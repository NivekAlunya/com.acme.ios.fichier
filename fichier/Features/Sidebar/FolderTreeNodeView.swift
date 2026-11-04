//
//  FolderTreeNodeView.swift
//  fichier
//

import SwiftUI

/// Recursive tree row that supports both expanding subfolders and selecting the folder to display its media
struct FolderTreeNodeView: View {
    let node: MediaItem
    let level: Int
    @State private var isExpanded: Bool
    var manager: StorageLocationManager
    let onSelectFolder: (MediaItem) -> Void
    
    init(
        node: MediaItem,
        level: Int,
        isInitiallyExpanded: Bool = false,
        manager: StorageLocationManager,
        onSelectFolder: @escaping (MediaItem) -> Void
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
    
    private var nodeIconName: String {
        if let customIcon = node.folderIconName {
            if customIcon == "rectangle.stack" && isSelected {
                return "rectangle.stack.fill"
            }
            return customIcon
        }
        
        if level == 0 {
            if manager.currentLocation?.kind == .photos {
                return "photo.on.rectangle.angled"
            } else if manager.currentLocation?.kind == .iCloudFolder {
                return "icloud.fill"
            } else if manager.currentLocation?.kind == .localFolder {
                return "folder.fill"
            }
            return "externaldrive.fill.badge.wifi"
        }
        return isSelected ? "folder.fill" : "folder"
    }
    
    private var nodeIconColor: Color {
        if node.folderIconName == "heart.fill" {
            return .pink
        }
        if node.locationID == StorageLocation.photosLocationID {
            return isSelected ? .pink : .secondary
        }
        return isSelected ? .blue : .accentColor
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
            
            // Folder selection button (loads media, expands tree & navigates to detail view)
            Button {
                withAnimation(.snappy) {
                    isExpanded = true
                }
                onSelectFolder(node)
                if node.children == nil {
                    Task {
                        await manager.loadSubfoldersForTree(at: node)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: nodeIconName)
                        .foregroundColor(nodeIconColor)
                    
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
        .task {
            if isExpanded && node.children == nil {
                await manager.loadSubfoldersForTree(at: node)
            }
        }
        .task(id: manager.selectedFolder?.id) {
            guard let selected = manager.selectedFolder else { return }
            if selected.id == node.id || isAncestor(of: selected) {
                if !isExpanded {
                    withAnimation(.snappy) {
                        isExpanded = true
                    }
                }
                if node.children == nil {
                    await manager.loadSubfoldersForTree(at: node)
                }
            }
        }
        
        // Render child subfolders recursively when expanded
        if isExpanded, let children = node.children {
            ForEach(children) { child in
                FolderTreeNodeView(
                    node: child,
                    level: level + 1,
                    isInitiallyExpanded: shouldChildBeInitiallyExpanded(child),
                    manager: manager,
                    onSelectFolder: onSelectFolder
                )
            }
        }
    }
    
    private func isAncestor(of target: MediaItem) -> Bool {
        guard target.locationID == node.locationID, target.rootName == node.rootName else { return false }
        if node.path == "/" || node.path.isEmpty {
            return target.path != node.path
        }
        let normalizedNode = node.path.replacingOccurrences(of: "\\", with: "/")
        let normalizedTarget = target.path.replacingOccurrences(of: "\\", with: "/")
        let nodeComponents = normalizedNode.split(separator: "/").filter { !$0.isEmpty }
        let targetComponents = normalizedTarget.split(separator: "/").filter { !$0.isEmpty }
        return targetComponents.starts(with: nodeComponents) && targetComponents.count > nodeComponents.count
    }
    
    private func shouldChildBeInitiallyExpanded(_ child: MediaItem) -> Bool {
        guard let selected = manager.selectedFolder else { return false }
        if selected.id == child.id { return true }
        guard selected.locationID == child.locationID, selected.rootName == child.rootName else { return false }
        if child.path.isEmpty || child.path == "/" { return true }
        let normalizedChild = child.path.replacingOccurrences(of: "\\", with: "/")
        let normalizedSelected = selected.path.replacingOccurrences(of: "\\", with: "/")
        let childComponents = normalizedChild.split(separator: "/").filter { !$0.isEmpty }
        let selectedComponents = normalizedSelected.split(separator: "/").filter { !$0.isEmpty }
        return selectedComponents.starts(with: childComponents)
    }
}
