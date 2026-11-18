//
//  FolderCardView.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Large folder card: linked thumbnail as full-bleed background, frosted bottom bar with the folder name.
///
/// Falls back to a tinted background with a large folder glyph when no thumbnail is linked yet.
struct FolderCardView: View {
    /// Folder to render.
    let folder: MediaItem

    /// Linked thumbnail, if one exists.
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                nameBar
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
    private var background: some View {
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
                Color.blue.opacity(0.12)
                Image(systemName: folder.folderIconName ?? "folder.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue.gradient)
            }
        }
    }

    private var nameBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.caption)
            Text(folder.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2)
        }
        .foregroundColor(thumbnail == nil ? .primary : .white)
        .shadow(color: .black.opacity(thumbnail == nil ? 0 : 0.35), radius: 1, y: 1)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.black.opacity(thumbnail == nil ? 0 : 0.45)
                .background(thumbnail == nil ? AnyShapeStyle(.clear) : AnyShapeStyle(.ultraThinMaterial))
        )
    }
}
