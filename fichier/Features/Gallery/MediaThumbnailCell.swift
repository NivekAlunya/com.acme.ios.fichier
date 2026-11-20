//
//  MediaThumbnailCell.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Visual grid card presenting a single media asset within `MediaGridView`.
///
/// Features an edge-to-edge downsampled thumbnail, top badges (format capsule, favorites, selection),
/// and an ultra-thin material frosted glass footer detailing the item's filename and secondary metadata.
struct MediaThumbnailCell: View {
    /// Storage location manager providing thumbnail caching and retrieval.
    var manager: StorageLocationManager
    
    /// Target media item displayed in this grid cell.
    let item: MediaItem
    
    /// Grid density sizing used for responsive typography and badge scaling.
    var gridSize: GridSize = .medium
    
    /// Maximum pixel bounding dimension for downsampled thumbnail decoding.
    var maxDimension: CGFloat = 260
    
    /// Indicates whether this cell is checked in multi-selection mode.
    var isSelected: Bool = false
    
    /// Indicates whether the gallery is currently in multi-selection editing mode.
    var isSelectionMode: Bool = false
    
    /// Cached secondary metadata details resolved asynchronously.
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
    
    /// Format metadata resolved in a single pass.
    private var formatInfo: (label: String, color: Color, pictogramName: String) {
        MediaItemFormatStyle.formatInfo(for: item)
    }

    var body: some View {
        ZStack {
            MediaThumbnailView(
                manager: manager,
                item: item,
                maxDimension: maxDimension,
                cornerRadius: 12,
                isCompact: false,
                showsBadges: false
            )
            .aspectRatio(1, contentMode: .fit)
            
            VStack(spacing: 0) {
                topTrailingBadge
                Spacer(minLength: 0)
                bottomOverlayBar
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? FichierTheme.accent : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 3 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .task(id: item.id) {
            guard !item.isDirectory, displayedDetail == nil else { return }
            mediaDetail = await MediaDetailStore.shared.resolveDetail(for: item.asMediaSourceItem)
        }
    }
    
    // MARK: - Top Trailing Badge
    
    /// Top-trailing overlay displaying the format capsule (picto + extension), favorite indicator, and selection checkbox.
    @ViewBuilder
    private var topTrailingBadge: some View {
        HStack(spacing: 5) {
            if FavoritesManager.shared.isFavorite(item) {
                Image(systemName: "heart.fill")
                    .font(gridSize.iconFont)
                    .foregroundColor(.red)
                    .padding(4)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            
            Spacer(minLength: 4)
            
            formatCapsule
            
            if isSelectionMode {
                let checkSize: CGFloat = gridSize == .large ? 24 : 20
                ZStack {
                    Circle()
                        .fill(isSelected ? FichierTheme.accent : Color.black.opacity(0.45))
                        .frame(width: checkSize, height: checkSize)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(gridSize.iconFont)
                            .foregroundColor(.white)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: isSelected ? 0 : 1.3)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(gridSize == .large ? 8 : 6)
    }
    
    /// Capsule badge at top trailing edge with picto + extension tinted by formatColor.
    @ViewBuilder
    private var formatCapsule: some View {
        let info = formatInfo
        HStack(spacing: gridSize == .large ? 3.5 : 2.5) {
            Image(systemName: info.pictogramName)
                .font(gridSize.iconFont)
            
            Text(info.label)
                .font(gridSize.capsuleFont)
            
            if item.isVideo {
                videoPlaybackIndicator
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, gridSize == .large ? 6 : 4.5)
        .padding(.vertical, gridSize == .large ? 3 : 2)
        .background(info.color.opacity(0.85))
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Bottom Overlay Bar
    
    /// Edge-to-edge footer displaying merged title, file size, detail, and video progress.
    @ViewBuilder
    private var bottomOverlayBar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: gridSize == .large ? 3 : 2) {
                // Merged item title (1 line in compact mode, up to 2 lines in medium/large)
                Text(item.name)
                    .font(gridSize.titleFont)
                    .foregroundColor(.white)
                    .lineLimit(gridSize == .compact ? 1 : 2)
                    .truncationMode(.middle)
                    .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
                
                // Metadata line (info)
                HStack(spacing: 3) {
                    Text(item.formattedSize)
                    if let detail = displayedDetail, !detail.isEmpty {
                        Text("•")
                        Text(detail)
                    }
                }
                .font(gridSize.detailFont)
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
                .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
            }
            .padding(.horizontal, gridSize == .large ? 10 : 8)
            .padding(.vertical, gridSize == .large ? 6 : (gridSize == .compact ? 4 : 5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.black.opacity(0.45)
                    .background(.ultraThinMaterial)
            )
        }
    }
    
    /// Playback state indicator icon or progress ring for video files.
    @ViewBuilder
    private var videoPlaybackIndicator: some View {
        let playbackStatus = VideoPlaybackStore.shared.status(for: item)
        switch playbackStatus {
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(gridSize.iconFont)
                .foregroundColor(.green)
        case .inProgress(let progress):
            VideoProgressRing(
                progress: progress,
                size: gridSize == .large ? 12 : 9,
                lineWidth: 1.4,
                ringColor: .white
            )
        case .unwatched:
            EmptyView()
        }
    }
}
