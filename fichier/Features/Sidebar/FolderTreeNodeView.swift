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
        .task(id: isExpanded) {
            if isExpanded && node.children == nil {
                await manager.loadSubfoldersForTree(at: node)
            }
        }
        .onChange(of: manager.selectedFolder) { _, newSelected in
            guard let newSelected else { return }
            if !isExpanded && (newSelected.id == node.id || isAncestor(of: newSelected)) {
                withAnimation(.snappy) {
                    isExpanded = true
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
        // Fast-path rejection: discard completely non-matching paths with 0 allocations
        guard target.path.hasPrefix(node.path) else { return false }
        let nodeComponents = node.normalizedComponents
        let targetComponents = target.normalizedComponents
        return targetComponents.starts(with: nodeComponents) && targetComponents.count > nodeComponents.count
    }
    
    private func shouldChildBeInitiallyExpanded(_ child: MediaItem) -> Bool {
        guard let selected = manager.selectedFolder else { return false }
        if selected.id == child.id { return true }
        guard selected.locationID == child.locationID, selected.rootName == child.rootName else { return false }
        if child.path.isEmpty || child.path == "/" { return true }
        // Fast-path rejection: discard non-matching branches before substring parsing
        guard selected.path.hasPrefix(child.path) else { return false }
        return selected.normalizedComponents.starts(with: child.normalizedComponents)
    }
}
