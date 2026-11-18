//
//  MediaFolderContextMenu.swift
//  fichier
//

import SwiftUI

/// Reusable context menu actions presented when long-pressing a directory folder item.
public struct MediaFolderContextMenu: View {
    public let folder: MediaItem
    public let canManage: Bool
    public let onRequestRename: ((MediaItem) -> Void)?
    public let onRequestMove: ((MediaItem) -> Void)?
    public let onRequestDelete: ((MediaItem) -> Void)?

    public init(
        folder: MediaItem,
        canManage: Bool,
        onRequestRename: ((MediaItem) -> Void)? = nil,
        onRequestMove: ((MediaItem) -> Void)? = nil,
        onRequestDelete: ((MediaItem) -> Void)? = nil
    ) {
        self.folder = folder
        self.canManage = canManage
        self.onRequestRename = onRequestRename
        self.onRequestMove = onRequestMove
        self.onRequestDelete = onRequestDelete
    }

    public var body: some View {
        if canManage {
            Button {
                onRequestRename?(folder)
            } label: {
                Label(.Strings.galleryActionRename, systemImage: "pencil")
            }

            Button {
                onRequestMove?(folder)
            } label: {
                Label(.Strings.galleryActionMoveToFolder, systemImage: "folder")
            }

            Button(role: .destructive) {
                onRequestDelete?(folder)
            } label: {
                Label(.Strings.commonDelete, systemImage: "trash")
            }
        }
    }
}
