//
//  FolderCardView.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Padded folder card matching `MediaThumbnailCell` and tvOS `TVMediaGridItemView`.
///
/// Renders a 4:3 inner thumbnail (linked folder icon or `FichierTheme.accent` placeholder)
/// with a bottom-leading `FOLDER` badge and the folder name below the thumbnail.
struct FolderCardView: View {
    /// Folder to render.
    let folder: MediaItem

    /// Grid density sizing used for responsive typography, padding, and badge scaling.
    var gridSize: GridSize = .medium

    /// Linked thumbnail, if one exists.
    @State private var thumbnail: UIImage?

    @Environment(\.colorScheme) private var colorScheme

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color(white: 0.96)
    }

    private var cardPadding: CGFloat {
        gridSize == .large ? 8 : 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: gridSize == .large ? 6 : 5) {
            thumbnailView
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            footerBar
        }
        .padding(cardPadding)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .task(id: folder.id) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let loaded = await MediaCacheManager.shared.folderIcon(
            folderPath: folder.path,
            shareName: folder.shareName,
            connectionID: folder.connectionID
        )
        guard !Task.isCancelled else { return }
        thumbnail = loaded
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Color.clear
                .overlay {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            ZStack {
                FichierTheme.accent.opacity(0.14)
                Image(systemName: folder.folderIconName ?? "folder.fill")
                    .font(.largeTitle)
                    .foregroundStyle(FichierTheme.accent.gradient)
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 6) {
            Text(folder.name)
                .font(gridSize.titleFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }
}
