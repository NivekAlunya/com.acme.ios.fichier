//
//  TVMediaListRowView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// A list row for Shares presenting full-row highlight and metadata within a 100-120 pt height.
public struct TVMediaListRowView: View {
    public let item: MediaSourceItem

    public init(item: MediaSourceItem) {
        self.item = item
    }

    public var body: some View {
        HStack(spacing: 24) {
            leadingPreview
                .frame(width: 120, height: 80)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 16) {
                    if item.type != .folder && item.size > 0 {
                        Text(MediaFormatHelper.formatByteCount(item.size))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let date = item.modifiedDate {
                        Text(MediaFormatHelper.formatDate(date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            trailingAccessory
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(height: 110)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var leadingPreview: some View {
        TVThumbnailView(item: item, targetSize: CGSize(width: 120, height: 80))
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if item.type == .folder {
            Image(systemName: "chevron.right")
                .font(.headline)
                .foregroundStyle(.secondary)
        } else if item.type == .video {
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
        }
    }

    private var accessibilityDescription: String {
        switch item.type {
        case .folder:
            return "Folder: \(item.name)"
        case .video:
            return "Video: \(item.name), size \(MediaFormatHelper.formatByteCount(item.size))"
        case .image:
            return "Image: \(item.name), size \(MediaFormatHelper.formatByteCount(item.size))"
        }
    }
}
