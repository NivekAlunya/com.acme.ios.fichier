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
    let mediaSectionHeader: LocalizedStringResource
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
        mediaSectionHeader: LocalizedStringResource = .Strings.gallerySectionMediaCount(0),
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
        self.mediaSectionHeader = mediaSectionHeader
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
                                        .foregroundColor(FichierTheme.accent)
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
                                MediaFolderContextMenu(
                                    folder: subfolder,
                                    canManage: manager.canManageItem(subfolder),
                                    onRequestRename: onRequestRename,
                                    onRequestMove: onRequestMove,
                                    onRequestDelete: onRequestDelete
                                )
                            })
                        }
                    }
                    .id("topOfList")
                }
                
                if !pictures.isEmpty {
                    Section(String(localized: mediaSectionHeader)) {
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
                                MediaItemContextMenu(
                                    item: pic,
                                    canManage: manager.canManageItem(pic),
                                    onEnterSelectionMode: onEnterSelectionMode,
                                    onRequestRename: onRequestRename,
                                    onRequestMove: onRequestMove,
                                    onRequestDelete: onRequestDelete,
                                    onInvalidateThumbnail: { item in
                                        await manager.invalidateThumbnail(for: item)
                                    }
                                )
                            })
                        }
                    }
                    .id(folders.isEmpty ? "topOfList" : "picturesSection")
                }
            }
            #if !os(tvOS)
            .scrollDismissesKeyboard(.immediately)
            .scrollContentBackground(.hidden)
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
