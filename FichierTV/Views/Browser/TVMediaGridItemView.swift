//
//  TVMediaGridItemView.swift
//  FichierTV
//
//

import SwiftUI
import FichierKit

/// Portrait edge-to-edge grid card for the tvOS media browser.
///
/// Features a 3:4 portrait thumbnail with compact top/bottom gradient scrims,
/// top title and video watched checkmark overlays, bottom-leading format capsule,
/// bottom-trailing resolution/duration and size metadata, and a bottom-edge video progress bar.
public struct TVMediaGridItemView: View {
    private static let topScrim = LinearGradient(
        colors: [Color.black.opacity(0.60), Color.clear],
        startPoint: .top,
        endPoint: .bottom
    )

    private static let bottomScrim = LinearGradient(
        colors: [Color.clear, Color.black.opacity(0.65)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Target media source item displayed in this grid cell.
    public let item: MediaSourceItem

    /// Resolved lightweight media detail (video duration or image frame dimensions).
    @State private var mediaDetail: String?

    @Environment(\.isFocused) private var isFocused

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

    private var formatInfo: (label: String, color: Color, pictogramName: String) {
        TVMediaItemFormatStyle.formatInfo(for: item)
    }

    private var isVideoFinished: Bool {
        guard item.type == .video else { return false }
        if case .finished = VideoPlaybackStore.shared.status(for: item) {
            return true
        }
        return false
    }

    /// Designated public initializer.
    ///
    /// - Parameter item: Target media source item.
    public init(item: MediaSourceItem) {
        self.item = item
    }

    public var body: some View {
        TVThumbnailView(item: item, targetSize: CGSize(width: 420, height: 560))
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.12))
            .overlay(alignment: .top) {
                topOverlay
            }
            .overlay(alignment: .bottom) {
                bottomOverlay
            }
            .overlay(alignment: .bottom) {
                videoProgressBar
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isFocused ? FichierTheme.secondaryAccent : Color.white.opacity(0.14),
                        lineWidth: isFocused ? 3 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription)
            .task(id: item.id) {
                guard item.type != .folder, displayedDetail == nil else { return }
                mediaDetail = await MediaDetailStore.shared.resolveDetail(for: item)
            }
    }

    // MARK: - Thumbnail Overlays

    @ViewBuilder
    private var topOverlay: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(item.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isVideoFinished {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(FichierTheme.secondaryAccent)
                    .padding(6)
                    .background(Color.black.opacity(0.45), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(Self.topScrim)
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        let hasDetail = displayedDetail?.isEmpty == false
        let hasSize = item.type != .folder && item.size > 0

        HStack(alignment: .bottom, spacing: 6) {
            formatCapsule

            Spacer(minLength: 4)

            if hasDetail || hasSize {
                VStack(alignment: .trailing, spacing: 2) {
                    if hasDetail, let detail = displayedDetail {
                        Text(detail)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    if hasSize {
                        Text(MediaFormatHelper.formatByteCount(item.size))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .padding(.top, 18)
        .background(Self.bottomScrim)
    }

    @ViewBuilder
    private var formatCapsule: some View {
        let info = formatInfo
        HStack(spacing: 5) {
            Image(systemName: info.pictogramName)
                .font(.system(size: 12, weight: .bold))

            Text(info.label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background((item.type == .folder ? FichierTheme.carbon : info.color).opacity(0.88), in: RoundedRectangle(cornerRadius: 6))
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
