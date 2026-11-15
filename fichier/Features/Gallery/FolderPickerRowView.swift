//
//  FolderPickerRowView.swift
//  fichier
//

import SwiftUI

/// Row view displaying a selectable folder node within `FolderPickerSheetView`.
struct FolderPickerRowView: View {
    /// The folder item represented by this row.
    let folder: MediaItem
    
    /// Nesting indentation depth level.
    let level: Int
    
    /// Whether this row is currently chosen as the move destination.
    let isSelected: Bool
    
    /// Whether this folder node's children are currently visible.
    let isExpanded: Bool
    
    /// Whether this folder can be selected as a valid destination.
    let isEnabled: Bool
    
    /// Whether this folder is actively loading its child subfolders.
    var isLoading: Bool = false
    
    /// Action triggered when toggling disclosure chevron.
    let onToggleExpand: () -> Void
    
    /// Action triggered when tapping the row to select it.
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            if level > 0 {
                Spacer()
                    .frame(width: CGFloat(level) * 16)
            }
            
            if isLoading {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 20, height: 20)
            } else if folder.children?.isEmpty == true {
                Spacer()
                    .frame(width: 20)
            } else {
                Button {
                    onToggleExpand()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            
            Button {
                if isEnabled {
                    onSelect()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "folder.fill" : "folder")
                        .foregroundColor(isEnabled ? (isSelected ? .blue : .accentColor) : .secondary)
                        .font(.system(size: 18))
                    
                    Text(folder.name.isEmpty ? folder.rootName : folder.name)
                        .font(.body)
                        .foregroundColor(isEnabled ? .primary : .secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
        .padding(.vertical, 4)
    }
}
