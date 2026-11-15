//
//  MediaThumbnailCell.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Grid cell view displaying a media item's thumbnail, file metadata, and interactive selection badges.
///
/// Wraps `MediaThumbnailView` with square 1:1 aspect ratio, selection highlight borders,
/// favorite heart icons, and multi-selection checkboxes.
struct MediaThumbnailCell: View {
    /// Storage location manager providing thumbnail caching and retrieval.
    var manager: StorageLocationManager
    
    /// Target media item displayed in this grid cell.
    let item: MediaItem
    
    /// Maximum pixel bounding dimension for downsampled thumbnail decoding.
    var maxDimension: CGFloat = 260
    
    /// Indicates whether this cell is checked in multi-selection mode.
    var isSelected: Bool = false
    
    /// Indicates whether the gallery is currently in multi-selection editing mode.
    var isSelectionMode: Bool = false

    /// Resolved lightweight media detail (video duration, image frame dimensions, or PDF page count).
    @State private var mediaDetail: String? = nil
    
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
        VStack(alignment: .leading, spacing: 4) {
            MediaThumbnailView(
                manager: manager,
                item: item,
                maxDimension: maxDimension,
                cornerRadius: 10,
                isCompact: false
            )
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                selectionOrFavoriteOverlay
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
            )
            
            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(item.formattedSize)
                if let detail = displayedDetail {
                    Text("•")
                    Text(detail)
                }
            }
            .font(.system(size: 9))
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        .task(id: item.id) {
            guard !item.isDirectory, displayedDetail == nil else { return }
            mediaDetail = await MediaDetailStore.shared.resolveDetail(for: item.asMediaSourceItem)
        }
    }
    
    /// Visual overlay displaying a checkmark circle during selection mode or a red heart for favorites.
    @ViewBuilder
    private var selectionOrFavoriteOverlay: some View {
        if isSelectionMode {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.blue : Color.black.opacity(0.4))
                    .frame(width: 24, height: 24)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: isSelected ? 0 : 1.5)
            )
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .transition(.scale.combined(with: .opacity))
        } else if FavoritesManager.shared.isFavorite(item) {
            Image(systemName: "heart.fill")
                .font(.system(size: 10))
                .foregroundColor(.red)
                .padding(5)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }
}
