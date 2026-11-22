//
//  MediaThumbnailCell.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Padded media card presenting a single asset within `MediaGridView`.
///
/// Features a rounded thumbnail with top-leading favorite / top-trailing Mint selection overlays,
/// a bottom-leading format capsule, a Peach playback progress bar along the thumbnail's bottom edge,
/// and a footer below the thumbnail displaying the title and size/detail metadata.
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

    @Environment(\.colorScheme) private var colorScheme

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

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color(white: 0.96)
    }

    private var cardPadding: CGFloat {
        gridSize == .large ? 8 : 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: gridSize == .large ? 6 : 5) {
            MediaThumbnailView(
                manager: manager,
                item: item,
                maxDimension: maxDimension,
                cornerRadius: 8,
                isCompact: false,
                showsBadges: false
            )
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .top) {
                topStatusOverlay
            }
            .overlay(alignment: .bottomLeading) {
                formatCapsule
                    .padding(gridSize == .large ? 6 : 4)
            }
            .overlay(alignment: .bottom) {
                videoProgressBar
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            footerMetadata
        }
        .padding(cardPadding)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? FichierTheme.secondaryAccent : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 2.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .task(id: item.id) {
            guard !item.isDirectory, displayedDetail == nil else { return }
            mediaDetail = await MediaDetailStore.shared.resolveDetail(for: item.asMediaSourceItem)
        }
    }

    // MARK: - Thumbnail Overlays

    @ViewBuilder
    private var topStatusOverlay: some View {
        HStack(spacing: 4) {
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

            if isSelectionMode {
                let checkSize: CGFloat = gridSize == .large ? 24 : 20
                Circle()
                    .fill(isSelected ? FichierTheme.secondaryAccent : Color.black.opacity(0.45))
                    .frame(width: checkSize, height: checkSize)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(gridSize.iconFont)
                                .foregroundColor(FichierTheme.onAccentDark)
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
        .padding(gridSize == .large ? 6 : 4)
    }

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
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    private var videoProgressBar: some View {
        if item.isVideo, case .inProgress(let progress) = VideoPlaybackStore.shared.status(for: item), progress > 0 {
            ProgressView(value: min(max(progress, 0), 1))
                .progressViewStyle(.linear)
                .tint(FichierTheme.tertiaryAccent)
                .background(Color.black.opacity(0.35))
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerMetadata: some View {
        VStack(alignment: .leading, spacing: gridSize == .large ? 3 : 2) {
            Text(item.name)
                .font(gridSize.titleFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 3) {
                Text(item.formattedSize)
                if let detail = displayedDetail, !detail.isEmpty {
                    Text("•")
                    Text(detail)
                }
            }
            .font(gridSize.detailFont)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Playback state indicator icon for completed video files.
    @ViewBuilder
    private var videoPlaybackIndicator: some View {
        if case .finished = VideoPlaybackStore.shared.status(for: item) {
            Image(systemName: "checkmark.circle.fill")
                .font(gridSize.iconFont)
                .foregroundColor(FichierTheme.secondaryAccent)
        }
    }
}
