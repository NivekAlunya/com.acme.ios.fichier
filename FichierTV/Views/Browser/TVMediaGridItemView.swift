//
//  TVMediaGridItemView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Translucent glass grid card for the tvOS media browser matching the Continue Watching card design.
///
/// Features:
/// - Padded glass container with 16pt corner radius and focus-reactive border.
/// - Inner thumbnail (12pt corner radius) with bottom-leading format badge and bottom-edge Peach progress bar.
/// - Footer below the thumbnail displaying title and size/detail metadata.
public struct TVMediaGridItemView: View {
    /// Target media source item displayed in this grid cell.
    public let item: MediaSourceItem

    /// Resolved lightweight media detail (video duration, image frame dimensions, or PDF page count).
    @State private var mediaDetail: String?

    @Environment(\.isFocused) private var isFocused

    /// Synchronously resolved detail prioritizing in-memory cache and playback store before async tasks.
    private var displayedDetail: String? {
        _ = MediaDetailStore.shared.revision
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

    /// Designated public initializer.
    ///
    /// - Parameter item: Target media source item.
    public init(item: MediaSourceItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TVThumbnailView(item: item, targetSize: CGSize(width: 440, height: 330))
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomLeading) {
                    formatCapsule
                        .padding(10)
                }
                .overlay(alignment: .bottom) {
                    videoProgressBar
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

            footerMetadata
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isFocused ? FichierTheme.surfaceMid.opacity(0.45) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isFocused ? FichierTheme.secondaryAccent : Color.white.opacity(0.12),
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .task(id: item.id) {
            guard item.type != .folder, displayedDetail == nil else { return }
            mediaDetail = await MediaDetailStore.shared.resolveDetail(for: item)
        }
    }

    // MARK: - Thumbnail Overlays

    /// Rounded format badge at bottom-leading of the thumbnail tinted by formatColor.
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
        .background((item.type == .folder ? FichierTheme.carbon : info.color).opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
    }

    @ViewBuilder
    private var videoProgressBar: some View {
        if item.type == .video, case .inProgress(let progress) = VideoPlaybackStore.shared.status(for: item), progress > 0 {
            ProgressView(value: min(max(progress, 0), 1))
                .progressViewStyle(.linear)
                .tint(FichierTheme.tertiaryAccent)
                .background(Color.black.opacity(0.35))
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerMetadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)

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
            .foregroundColor(.white.opacity(0.7))
            .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Playback Indicator

    /// Playback state indicator icon for completed video files.
    @ViewBuilder
    private var videoPlaybackIndicator: some View {
        if case .finished = VideoPlaybackStore.shared.status(for: item) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(FichierTheme.secondaryAccent)
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
