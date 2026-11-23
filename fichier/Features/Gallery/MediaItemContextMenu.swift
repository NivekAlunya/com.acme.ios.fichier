//
//  MediaItemContextMenu.swift
//  fichier
//

import SwiftUI

/// Reusable context menu actions presented when long-pressing a file or media asset.
public struct MediaItemContextMenu: View {
    public let item: MediaItem
    public let canManage: Bool
    public let onEnterSelectionMode: (MediaItem) -> Void
    public let onRequestRename: ((MediaItem) -> Void)?
    public let onRequestMove: ((MediaItem) -> Void)?
    public let onRequestDelete: ((MediaItem) -> Void)?
    public let onRequestSaveToPhotos: ((MediaItem) -> Void)?
    public let onRequestDownloadToFiles: ((MediaItem) -> Void)?
    public let onInvalidateThumbnail: (MediaItem) async -> Void

    public init(
        item: MediaItem,
        canManage: Bool,
        onEnterSelectionMode: @escaping (MediaItem) -> Void,
        onRequestRename: ((MediaItem) -> Void)? = nil,
        onRequestMove: ((MediaItem) -> Void)? = nil,
        onRequestDelete: ((MediaItem) -> Void)? = nil,
        onRequestSaveToPhotos: ((MediaItem) -> Void)? = nil,
        onRequestDownloadToFiles: ((MediaItem) -> Void)? = nil,
        onInvalidateThumbnail: @escaping (MediaItem) async -> Void
    ) {
        self.item = item
        self.canManage = canManage
        self.onEnterSelectionMode = onEnterSelectionMode
        self.onRequestRename = onRequestRename
        self.onRequestMove = onRequestMove
        self.onRequestDelete = onRequestDelete
        self.onRequestSaveToPhotos = onRequestSaveToPhotos
        self.onRequestDownloadToFiles = onRequestDownloadToFiles
        self.onInvalidateThumbnail = onInvalidateThumbnail
    }

    public var body: some View {
        Button {
            onEnterSelectionMode(item)
        } label: {
            Label(.Strings.galleryButtonSelect, systemImage: "checkmark.circle")
        }

        if canManage {
            Button {
                onRequestRename?(item)
            } label: {
                Label(.Strings.galleryActionRename, systemImage: "pencil")
            }

            Button {
                onRequestMove?(item)
            } label: {
                Label(.Strings.galleryActionMoveToFolder, systemImage: "folder")
            }

            Button(role: .destructive) {
                onRequestDelete?(item)
            } label: {
                Label(.Strings.commonDelete, systemImage: "trash")
            }
        }

        Button {
            FavoritesManager.shared.toggleFavorite(item)
        } label: {
            Label(
                FavoritesManager.shared.isFavorite(item)
                    ? .Strings.galleryActionRemoveFromFavorites
                    : .Strings.galleryActionAddToFavorites,
                systemImage: FavoritesManager.shared.isFavorite(item) ? "heart.slash" : "heart"
            )
        }

        if let onRequestSaveToPhotos {
            Button {
                onRequestSaveToPhotos(item)
            } label: {
                Label(.Strings.galleryActionSaveToPhotos, systemImage: "photo")
            }
        }

        if let onRequestDownloadToFiles {
            Button {
                onRequestDownloadToFiles(item)
            } label: {
                Label(.Strings.galleryActionDownloadToFiles, systemImage: "arrow.down.doc")
            }
        }

        Button {
            Task {
                await onInvalidateThumbnail(item)
            }
        } label: {
            Label(.Strings.galleryThumbnailRetryPreview, systemImage: "arrow.clockwise")
        }
    }
}
