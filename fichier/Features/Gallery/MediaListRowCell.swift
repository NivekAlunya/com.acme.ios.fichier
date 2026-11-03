//
//  MediaListRowCell.swift
//  fichier
//

import SwiftUI

struct MediaListRowCell: View {
    var manager: StorageLocationManager
    let item: MediaItem
    var isSelected: Bool = false
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
