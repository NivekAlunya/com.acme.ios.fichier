//
//  TVMediaGridItemView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Full-bleed card-styled grid cell for tvOS media browser matching the iOS design system.
///
/// Features:
/// - Full-bleed thumbnail rendering with 16pt corner radius.
/// - Top-trailing format capsule badge with pictogram icon, extension label, and video playback indicator.
/// - Bottom edge-to-edge frosted glass overlay bar displaying title and metadata.
public struct TVMediaGridItemView: View {
    /// Target media source item displayed in this grid cell.
    public let item: MediaSourceItem

    /// Resolved lightweight media detail (video duration, image frame dimensions, or PDF page count).
    @State private var mediaDetail: String?

    /// Synchronously resolved detail prioritizing in-memory cache and playback store before async tasks.
    private var displayedDetail: String? {
        if let cached = MediaDetailStore.shared.cachedDetail(for: item.id) {
            return cached
        }
        if item.type == .video, let rec = VideoPlaybackStore.shared.records[item.id], rec.duration > 0 {
            return MediaFormatHelper.formatDuration(rec.duration)
        }
        return mediaDetail
    }

    /// Format metadata resolved in a single pass.
    private var formatInfo: (label: String, color: Color, pictogramName: String) {
        TVMediaItemFormatStyle.formatInfo(for: item)
    }

    /// Distinctive accent color resolved for this media item's container format.
    private var formatColor: Color {
        formatInfo.color
    }

    /// Display label for the media format capsule badge.
    private var formatLabel: String {
        formatInfo.label
    }

    /// Designated public initializer.
    ///
    /// - Parameter item: Target media source item.
    public init(item: MediaSourceItem) {
        self.item = item
    }

    public var body: some View {
        ZStack {
            TVThumbnailView(item: item, targetSize: CGSize(width: 440, height: 260))
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.12))

            VStack(spacing: 0) {
                topTrailingBadge
                Spacer(minLength: 0)
                bottomOverlayBar
            }
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .task(id: item.id) {
            guard item.type != .folder, displayedDetail == nil else { return }
            mediaDetail = await MediaDetailStore.shared.resolveDetail(for: item)
        }
    }

    // MARK: - Top Trailing Badge

    /// Top-trailing overlay displaying the format capsule (pictogram + extension + playback indicator).
    @ViewBuilder
    private var topTrailingBadge: some View {
        HStack {
            Spacer(minLength: 4)
            formatCapsule
        }
        .padding(10)
    }

    /// Capsule badge at top trailing edge with picto + extension tinted by formatColor.
    @ViewBuilder
    private var formatCapsule: some View {
        let info = formatInfo
        HStack(spacing: 6) {
            Image(systemName: info.pictogramName)
                .font(.system(size: 13, weight: .bold))

            Text(info.label)
                .font(.system(size: 14, weight: .bold, design: .rounded))

            if item.type == .video {
                videoPlaybackIndicator
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(info.color.opacity(0.85))
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
    }

    // MARK: - Bottom Overlay Bar

    /// Edge-to-edge footer displaying merged title, file size/count, and media details over frosted dark glass.
    @ViewBuilder
    private var bottomOverlayBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Merged item title
            Text(item.name)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .truncationMode(.middle)
                .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 1)

            // Metadata line (info)
            HStack(spacing: 6) {
                if item.type != .folder && item.size > 0 {
                    Text(MediaFormatHelper.formatByteCount(item.size))
                }
                if let detail = displayedDetail, !detail.isEmpty {
                    if item.type != .folder && item.size > 0 {
                        Text("•")
                    }
                    Text(detail)
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.95))
            .lineLimit(1)
            .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.black.opacity(0.45)
                .background(.ultraThinMaterial)
        )
    }

    // MARK: - Playback Indicator

    /// Playback state indicator icon or progress ring for video files.
    @ViewBuilder
    private var videoPlaybackIndicator: some View {
        let playbackStatus = VideoPlaybackStore.shared.status(for: item)
        switch playbackStatus {
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.green)
        case .inProgress(let progress):
            TVVideoProgressRing(
                progress: progress,
                size: 14,
                lineWidth: 2.0,
                ringColor: .white
            )
        case .unwatched:
            EmptyView()
        }
    }

    private var accessibilityDescription: String {
        switch item.type {
        case .folder:
            return "Folder: \(item.name)"
        case .video:
            return "Video: \(item.name)"
        case .image:
            return "Image: \(item.name)"
        }
    }
}
