//
//  MediaThumbnailCell.swift
//  fichier
//
//

import SwiftUI
import FichierKit

/// Portrait edge-to-edge media card presenting photos, videos, and documents within `MediaGridView`.
///
/// Features a 3:4 portrait thumbnail with compact top/bottom gradient scrims for legibility,
/// top favorite / title / selection or watched checkmark overlays, a bottom-leading format capsule,
/// bottom-trailing resolution/duration/page and size metadata, and a bottom-edge video progress bar.
struct MediaThumbnailCell: View {
    private static let topScrim = LinearGradient(
        colors: [Color.black.opacity(0.55), Color.clear],
        startPoint: .top,
        endPoint: .bottom
    )

    private static let bottomScrim = LinearGradient(
        colors: [Color.clear, Color.black.opacity(0.60)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Storage location manager providing thumbnail caching and retrieval.
    var manager: StorageLocationManager

    /// Target media item displayed in this grid cell.
    let item: MediaItem

    /// Grid density sizing used for responsive typography and badge scaling.
    var gridSize: GridSize = .medium

    /// Maximum pixel bounding dimension for downsampled thumbnail decoding.
    var maxDimension: CGFloat = MediaCacheManager.standardThumbnailDimension

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

    private var formatInfo: (label: String, color: Color, pictogramName: String) {
        MediaItemFormatStyle.formatInfo(for: item)
    }

    private var isFavorite: Bool {
        FavoritesManager.shared.isFavorite(item)
    }

    private var isVideoFinished: Bool {
        guard item.isVideo else { return false }
        if case .finished = VideoPlaybackStore.shared.status(for: item) {
            return true
        }
        return false
    }

    var body: some View {
        MediaThumbnailView(
            manager: manager,
            item: item,
            maxDimension: maxDimension,
            cornerRadius: 12,
            isCompact: false,
            showsBadges: false
        )
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .overlay(alignment: .top) {
            topStatusOverlay
        }
        .overlay(alignment: .bottom) {
            bottomOverlay
        }
        .overlay(alignment: .bottom) {
            videoProgressBar
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? FichierTheme.secondaryAccent : Color.primary.opacity(0.10),
                    lineWidth: isSelected ? 2.5 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: item.id) {
            guard !item.isDirectory, displayedDetail == nil else { return }
            mediaDetail = await MediaDetailStore.shared.resolveDetail(for: item.asMediaSourceItem)
        }
    }

    // MARK: - Thumbnail Overlays

    @ViewBuilder
    private var topStatusOverlay: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(item.name)
                .font(gridSize.titleFont)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isFavorite || isSelectionMode || isVideoFinished {
                HStack(spacing: 4) {
                    if isFavorite || (!isSelectionMode && isVideoFinished) {
                        statusCapsule
                    }
                    if isSelectionMode {
                        selectionBadge
                    }
                }
            }
        }
        .padding(.horizontal, gridSize == .large ? 8 : 6)
        .padding(.top, gridSize == .large ? 8 : 6)
        .padding(.bottom, 16)
        .background(Self.topScrim)
    }

    private var statusCapsule: some View {
        VStack(spacing: 4) {
            if isFavorite {
                favoriteIcon
            }
            if !isSelectionMode && isVideoFinished {
                videoFinishedBadge
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.45), in: Capsule())
    }

    private var favoriteIcon: some View {
        Image(systemName: "heart.fill")
            .font(gridSize.iconFont)
            .foregroundColor(.red)
    }

    private var videoFinishedBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(gridSize.iconFont)
            .foregroundColor(FichierTheme.secondaryAccent)
    }

    @ViewBuilder
    private var selectionBadge: some View {
        let checkSize: CGFloat = gridSize == .large ? 22 : 18
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
            .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        HStack(alignment: .bottom, spacing: 6) {
            formatCapsule

            Spacer(minLength: 4)

            bottomMetadataText
        }
        .padding(.horizontal, gridSize == .large ? 8 : 6)
        .padding(.bottom, gridSize == .large ? 8 : 6)
        .padding(.top, 16)
        .background(Self.bottomScrim)
    }

    @ViewBuilder
    private var formatCapsule: some View {
        let info = formatInfo
        HStack(spacing: gridSize == .large ? 3.5 : 2.5) {
            Image(systemName: info.pictogramName)
                .font(gridSize.iconFont)

            Text(info.label)
                .font(gridSize.capsuleFont)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundColor(.white)
        .padding(.horizontal, gridSize == .large ? 6 : 4.5)
        .padding(.vertical, gridSize == .large ? 3 : 2)
        .background(info.color.opacity(0.88), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var bottomMetadataText: some View {
        let hasDetail = gridSize != .compact && (displayedDetail?.isEmpty == false)
        let hasSize = item.size > 0
        if hasDetail || hasSize {
            VStack(alignment: .trailing, spacing: 1) {
                if hasDetail, let detail = displayedDetail {
                    Text(detail)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                if hasSize {
                    Text(item.formattedSize)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .font(gridSize.detailFont)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.92))
        }
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
}
