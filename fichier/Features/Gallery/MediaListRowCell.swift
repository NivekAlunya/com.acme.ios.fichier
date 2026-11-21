//
//  MediaListRowCell.swift
//  fichier
//

import SwiftUI
import FichierKit

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

    /// Resolved lightweight media detail (video duration, image frame dimensions, or PDF page count).
    @State private var mediaDetail: String?
    
    /// Synchronously resolved detail prioritizing in-memory cache and playback store before async tasks.
    private var displayedDetail: String? {
        if let cached = MediaDetailStore.shared.cachedDetail(for: item.id) {
            return cached
        }
        if item.isVideo, let rec = VideoPlaybackStore.shared.records[item.id], rec.duration > 0 {
            return MediaFormatHelper.formatDuration(rec.duration)
        }
        return mediaDetail
    }

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                ZStack {
                    Circle()
                        .fill(isSelected ? FichierTheme.connected : Color.clear)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
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
                        .font(.headline)
                        .lineLimit(2)
                    if FavoritesManager.shared.isFavorite(item) {
                        Image(systemName: "heart.fill")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
                HStack(spacing: 6) {
                    Text(item.formattedSize)
                    if let detail = displayedDetail {
                        Text("•")
                        Text(detail)
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .task(id: item.id) {
            guard !item.isDirectory, displayedDetail == nil else { return }
            mediaDetail = await MediaDetailStore.shared.resolveDetail(for: item.asMediaSourceItem)
        }
    }
}
