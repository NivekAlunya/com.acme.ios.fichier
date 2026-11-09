//
//  TVMediaGridItemView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// A focusable `.card` styled grid cell for photo, video, and folder items in the 4-column grid.
public struct TVMediaGridItemView: View {
    public let item: MediaSourceItem

    public init(item: MediaSourceItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                TVThumbnailView(item: item, targetSize: CGSize(width: 380, height: 260))
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                if item.type == .video {
                    videoBadge
                        .padding(10)
                } else if item.type == .folder {
                    folderBadge
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let date = item.modifiedDate {
                    Text(MediaFormatHelper.formatDate(date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if item.type != .folder && item.size > 0 {
                    Text(MediaFormatHelper.formatByteCount(item.size))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var videoBadge: some View {
        Image(systemName: "video.fill")
            .font(.caption2)
            .padding(6)
            .background(.ultraThinMaterial, in: Circle())
    }

    @ViewBuilder
    private var folderBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .font(.caption2)

            if item.size > 0 {
                Text("\(item.size)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
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
