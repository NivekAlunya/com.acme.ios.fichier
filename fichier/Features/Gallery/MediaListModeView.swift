//
//  MediaListModeView.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Vertical list mode presentation rendering subfolders and detailed media metadata rows.
@MainActor
struct MediaListModeView: View {
    let manager: StorageLocationManager
    let folders: [MediaItem]
    let pictures: [MediaItem]
    let isSelectionMode: Bool
    let selectedItems: Set<MediaItem>
    let currentDirectoryID: String
    let onNavigateToFolder: (MediaItem) -> Void
    let onSelectPicture: (MediaItem, [MediaItem]) -> Void
    let onToggleSelection: (MediaItem) -> Void
    let onEnterSelectionMode: (MediaItem) -> Void
    let onRefresh: () async -> Void
    var onRequestRename: ((MediaItem) -> Void)?
    var onRequestMove: ((MediaItem) -> Void)?
    var onRequestDelete: ((MediaItem) -> Void)?
    
    init(
        manager: StorageLocationManager,
        folders: [MediaItem],
        pictures: [MediaItem],
        isSelectionMode: Bool,
        selectedItems: Set<MediaItem>,
        currentDirectoryID: String,
        onNavigateToFolder: @escaping (MediaItem) -> Void,
        onSelectPicture: @escaping (MediaItem, [MediaItem]) -> Void,
        onToggleSelection: @escaping (MediaItem) -> Void,
        onEnterSelectionMode: @escaping (MediaItem) -> Void,
        onRefresh: @escaping () async -> Void,
        onRequestRename: ((MediaItem) -> Void)? = nil,
        onRequestMove: ((MediaItem) -> Void)? = nil,
        onRequestDelete: ((MediaItem) -> Void)? = nil
    ) {
        self.manager = manager
        self.folders = folders
        self.pictures = pictures
        self.isSelectionMode = isSelectionMode
        self.selectedItems = selectedItems
        self.currentDirectoryID = currentDirectoryID
        self.onNavigateToFolder = onNavigateToFolder
        self.onSelectPicture = onSelectPicture
        self.onToggleSelection = onToggleSelection
        self.onEnterSelectionMode = onEnterSelectionMode
        self.onRefresh = onRefresh
        self.onRequestRename = onRequestRename
        self.onRequestMove = onRequestMove
        self.onRequestDelete = onRequestDelete
    }
    
    private func mediaSectionHeader(for count: Int) -> LocalizedStringResource {
        .Strings.gallerySectionMediaCount(count)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !folders.isEmpty {
                    Section(String(localized: .Strings.gallerySectionSubfoldersCount(folders.count))) {
                        ForEach(folders) { subfolder in
                            Button {
                                onNavigateToFolder(subfolder)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder.fill")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(subfolder.name)
                                            .foregroundColor(.primary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .contextMenu(isSelectionMode ? nil : ContextMenu {
                                if manager.canManageItem(subfolder) {
                                    Button {
                                        onRequestRename?(subfolder)
                                    } label: {
                                        Label(.Strings.galleryActionRename, systemImage: "pencil")
                                    }
                                    
                                    Button {
                                        onRequestMove?(subfolder)
                                    } label: {
                                        Label(String(localized: "Move to Folder...", comment: "Context menu action to move folder"), systemImage: "folder")
                                    }
                                    
                                    Button(role: .destructive) {
                                        onRequestDelete?(subfolder)
                                    } label: {
                                        Label(String(localized: "Delete", comment: "Context menu action to delete folder"), systemImage: "trash")
                                    }
                                }
                            })
                        }
                    }
                    .id("topOfList")
                }
                
                if !pictures.isEmpty {
                    Section(String(localized: mediaSectionHeader(for: pictures.count))) {
                        ForEach(pictures) { pic in
                            Button {
                                if isSelectionMode {
                                    onToggleSelection(pic)
                                } else {
                                    onSelectPicture(pic, pictures)
                                }
                            } label: {
                                MediaListRowCell(
                                    manager: manager,
                                    item: pic,
                                    isSelected: selectedItems.contains(pic),
                                    isSelectionMode: isSelectionMode
                                )
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                LongPressGesture().onEnded { _ in
                                    if !isSelectionMode {
                                        onEnterSelectionMode(pic)
                                    }
                                }
                            )
                            .contextMenu(isSelectionMode ? nil : ContextMenu {
                                Button {
                                    onEnterSelectionMode(pic)
                                } label: {
                                    Label(String(localized: "Select", comment: "Context menu action to select item"), systemImage: "checkmark.circle")
                                }
                                
                                if manager.canManageItem(pic) {
                                    Button {
                                        onRequestRename?(pic)
                                    } label: {
                                        Label(.Strings.galleryActionRename, systemImage: "pencil")
                                    }
                                    
                                    Button {
                                        onRequestMove?(pic)
                                    } label: {
                                        Label(String(localized: "Move to Folder...", comment: "Context menu action to move item"), systemImage: "folder")
                                    }
                                    
                                    Button(role: .destructive) {
                                        onRequestDelete?(pic)
                                    } label: {
                                        Label(String(localized: "Delete", comment: "Context menu action to delete item"), systemImage: "trash")
                                    }
                                }
                                
                                Button {
                                    FavoritesManager.shared.toggleFavorite(pic)
                                } label: {
                                    Label(
                                        FavoritesManager.shared.isFavorite(pic) ? String(localized: "Remove from Favorites", comment: "Context menu unfavorite") : String(localized: "Add to Favorites", comment: "Context menu favorite"),
                                        systemImage: FavoritesManager.shared.isFavorite(pic) ? "heart.slash" : "heart"
                                    )
                                }
                                
                                Button {
                                    Task {
                                        await manager.invalidateThumbnail(for: pic)
                                    }
                                } label: {
                                    Label(.Strings.galleryThumbnailRetryPreview, systemImage: "arrow.clockwise")
                                }
                            })
                        }
                    }
                    .id(folders.isEmpty ? "topOfList" : "picturesSection")
                }
            }
            #if !os(tvOS)
            .scrollDismissesKeyboard(.immediately)
            #endif
            .id(currentDirectoryID)
            .onChange(of: currentDirectoryID) { _, _ in
                proxy.scrollTo("topOfList", anchor: .top)
            }
            .onChange(of: manager.isLoading) { wasLoading, isLoading in
                if wasLoading && !isLoading {
                    proxy.scrollTo("topOfList", anchor: .top)
                }
            }
            .refreshable {
                await onRefresh()
            }
        }
    }
}
