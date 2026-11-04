//
//  FolderTreeNodeView.swift
//  fichier
//

import SwiftUI

/// Recursive tree row view representing a single folder node in the hierarchical sidebar.
///
/// Supports independent disclosure chevron toggling and row selection:
/// - Tapping the disclosure chevron expands or collapses subfolders on demand via lazy loading.
/// - Tapping the row selects the folder, loads its pictures and child directories, and animates tree expansion.
/// - Recursively instantiates `FolderTreeNodeView` for every expanded child node with indented indentation (`level`).
struct FolderTreeNodeView: View {
    /// The media item folder represented by this tree node.
    let node: MediaItem
    
    /// Depth level of this node in the hierarchy (0 represents root shares).
    let level: Int
    
    /// Expansion state determining whether child subfolders are visible.
    @State private var isExpanded: Bool
    
    /// Centralized storage location manager.
    var manager: StorageLocationManager
    
    /// Callback triggered when the folder is selected for viewing in the media grid.
    let onSelectFolder: (MediaItem) -> Void
    
    /// Memberwise initializer with custom initial expansion state.
    ///
    /// - Parameters:
    ///   - node: Target folder media item.
    ///   - level: Tree nesting level.
    ///   - isInitiallyExpanded: Whether the node begins expanded.
    ///   - manager: Shared storage location manager.
    ///   - onSelectFolder: Folder selection handler.
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
    
    /// Indicates whether this folder is currently selected in the media manager.
    private var isSelected: Bool {
        manager.selectedFolder?.id == node.id
    }
    
    /// SF Symbol icon name representing the folder node based on storage backend, depth, and selection.
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
    
    /// Accent color for the folder symbol based on favorite status, Photos library, and selection.
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
    
    /// Tests whether this node is a strict directory ancestor of the target item.
    ///
    /// Appends a trailing slash boundary to prevent substring false-positives
    /// (e.g. `/Pictures/Cat` erroneously matching `/Pictures/Category`).
    ///
    /// - Parameter target: The candidate descendant media item.
    /// - Returns: `true` if this node is an ancestor directory of `target`.
    private func isAncestor(of target: MediaItem) -> Bool {
        guard target.locationID == node.locationID, target.rootName == node.rootName else { return false }
        if node.path == "/" || node.path.isEmpty {
            return target.path != node.path
        }
        // Directory boundary prefix check prevents false-positives like /Folder/Cat matching /Folder/Category
        let nodeBoundary = node.path.hasSuffix("/") ? node.path : "\(node.path)/"
        guard target.path.hasPrefix(nodeBoundary) else { return false }
        let nodeComponents = node.normalizedComponents
        let targetComponents = target.normalizedComponents
        return targetComponents.starts(with: nodeComponents) && targetComponents.count > nodeComponents.count
    }
    
    /// Evaluates whether a child folder node should automatically start expanded when rendered.
    ///
    /// - Parameter child: The child media item to inspect.
    /// - Returns: `true` if `child` is selected or is an ancestor of the currently selected folder.
    private func shouldChildBeInitiallyExpanded(_ child: MediaItem) -> Bool {
        guard let selected = manager.selectedFolder else { return false }
        if selected.id == child.id { return true }
        guard selected.locationID == child.locationID, selected.rootName == child.rootName else { return false }
        if child.path.isEmpty || child.path == "/" { return true }
        // Directory boundary prefix check prevents false-positives across sibling folders
        let childBoundary = child.path.hasSuffix("/") ? child.path : "\(child.path)/"
        guard selected.path.hasPrefix(childBoundary) else { return false }
        return selected.normalizedComponents.starts(with: child.normalizedComponents)
    }
}
