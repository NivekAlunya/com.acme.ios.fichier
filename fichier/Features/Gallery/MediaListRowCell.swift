//
//  MediaListRowCell.swift
//  fichier
//

import SwiftUI

/// Horizontal table row cell view used when `MediaGridView` is configured in `.list` view mode.
///
/// Features a compact thumbnail image (52x52 pt), title label with favorite indicator,
/// formatted file size and timestamp, and interactive selection checkbox toggles.
struct MediaListRowCell: View {
    /// Storage location manager providing thumbnail caching and retrieval.
    var manager: StorageLocationManager
    
    /// Target media item displayed in this row.
    let item: MediaItem
    
    /// Indicates whether this row is checked in multi-selection mode.
    var isSelected: Bool = false
    
    /// Indicates whether the gallery is currently in multi-selection editing mode.
    var isSelectionMode: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.clear)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.6), lineWidth: 1.5)
                )
                .transition(.scale.combined(with: .opacity))
            }
            
            MediaThumbnailView(
                manager: manager,
                item: item,
                maxDimension: 140,
                cornerRadius: 8,
                isCompact: true
            )
            .frame(width: 52, height: 52)
            .clipped()
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body)
                        .lineLimit(1)
                    if FavoritesManager.shared.isFavorite(item) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                HStack(spacing: 6) {
                    Text(item.formattedSize)
                    if let dateStr = item.formattedDate {
                        Text("•")
                        Text(dateStr)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
