//
//  MediaGridModeView.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Adaptive grid presentation featuring an optional subfolder shelf and a thumbnail matrix.
@MainActor
struct MediaGridModeView: View {
    let manager: StorageLocationManager
    let folders: [MediaItem]
    let pictures: [MediaItem]
    let gridColumns: [GridItem]
    let gridSize: GridSize
    let sortOption: SortOption
    let mediaSectionHeader: LocalizedStringResource
    let isSelectionMode: Bool
    let selectedItems: Set<MediaItem>
    let currentDirectoryID: String
    var viewerTransitionNamespace: Namespace.ID?
    let onNavigateToFolder: (MediaItem) -> Void
    let onSelectPicture: (MediaItem, [MediaItem]) -> Void
    let onToggleSelection: (MediaItem) -> Void
    let onEnterSelectionMode: (MediaItem) -> Void
    let onRefresh: () async -> Void
    var onRequestRename: ((MediaItem) -> Void)?
    var onRequestMove: ((MediaItem) -> Void)?
    var onRequestDelete: ((MediaItem) -> Void)?
    var onRequestSaveToPhotos: ((MediaItem) -> Void)?
    var onRequestDownloadToFiles: ((MediaItem) -> Void)?
    
    init(
        manager: StorageLocationManager,
        folders: [MediaItem],
        pictures: [MediaItem],
        gridColumns: [GridItem],
        gridSize: GridSize,
        sortOption: SortOption,
        mediaSectionHeader: LocalizedStringResource = .Strings.gallerySectionMediaCount(0),
        isSelectionMode: Bool,
        selectedItems: Set<MediaItem>,
        currentDirectoryID: String,
        viewerTransitionNamespace: Namespace.ID? = nil,
        onNavigateToFolder: @escaping (MediaItem) -> Void,
        onSelectPicture: @escaping (MediaItem, [MediaItem]) -> Void,
        onToggleSelection: @escaping (MediaItem) -> Void,
        onEnterSelectionMode: @escaping (MediaItem) -> Void,
        onRefresh: @escaping () async -> Void,
        onRequestRename: ((MediaItem) -> Void)? = nil,
        onRequestMove: ((MediaItem) -> Void)? = nil,
        onRequestDelete: ((MediaItem) -> Void)? = nil,
        onRequestSaveToPhotos: ((MediaItem) -> Void)? = nil,
        onRequestDownloadToFiles: ((MediaItem) -> Void)? = nil
    ) {
        self.manager = manager
        self.folders = folders
        self.pictures = pictures
        self.gridColumns = gridColumns
        self.gridSize = gridSize
        self.sortOption = sortOption
        self.mediaSectionHeader = mediaSectionHeader
        self.isSelectionMode = isSelectionMode
        self.selectedItems = selectedItems
        self.currentDirectoryID = currentDirectoryID
        self.viewerTransitionNamespace = viewerTransitionNamespace
        self.onNavigateToFolder = onNavigateToFolder
        self.onSelectPicture = onSelectPicture
        self.onToggleSelection = onToggleSelection
        self.onEnterSelectionMode = onEnterSelectionMode
        self.onRefresh = onRefresh
        self.onRequestRename = onRequestRename
        self.onRequestMove = onRequestMove
        self.onRequestDelete = onRequestDelete
        self.onRequestSaveToPhotos = onRequestSaveToPhotos
        self.onRequestDownloadToFiles = onRequestDownloadToFiles
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id("topOfGrid")
                
                VStack(alignment: .leading, spacing: 16) {
                    if !folders.isEmpty {
                        foldersSection
                    }
                    
                    if !pictures.isEmpty {
                        picturesSection
                    } else if !folders.isEmpty && !manager.isLoading {
                        emptyPicturesPlaceholder
                    }
                }
                .padding(.vertical, 12)
            }
            #if !os(tvOS)
            .scrollDismissesKeyboard(.immediately)
            #endif
            .onScrollPhaseChange { _, newPhase in
                ThumbnailPrefetchCoordinator.shared.setScrolling(newPhase != .idle)
            }
            .onDisappear {
                ThumbnailPrefetchCoordinator.shared.setScrolling(false)
            }
            .onChange(of: currentDirectoryID) { _, _ in
                proxy.scrollTo("topOfGrid", anchor: .top)
            }
            .refreshable {
                await onRefresh()
            }
        }
    }

    // MARK: - Subfolders Section

    @ViewBuilder
    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(.Strings.gallerySectionSubfoldersCount(folders.count), systemImage: "folder.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
            
            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(folders) { subfolder in
                    Button {
                        onNavigateToFolder(subfolder)
                    } label: {
                        FolderCardView(folder: subfolder, gridSize: gridSize)
                    }
                    .buttonStyle(.plain)
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
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Pictures Section

    @ViewBuilder
    private var picturesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(mediaSectionHeader)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Text(sortOption.localizedTitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(pictures) { pic in
                    pictureCell(for: pic)
                }
            }
            .padding(.horizontal, 12)
            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: gridSize)
        }
    }

    @ViewBuilder
    private func pictureCell(for pic: MediaItem) -> some View {
        MediaThumbnailCell(
            manager: manager,
            item: pic,
            gridSize: gridSize,
            maxDimension: gridSize.thumbnailPixels,
            isSelected: selectedItems.contains(pic),
            isSelectionMode: isSelectionMode
        )
        .optionalMatchedTransitionSource(id: pic.id, in: viewerTransitionNamespace)
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection(pic)
            } else {
                onSelectPicture(pic, pictures)
            }
        }
        .onLongPressGesture {
            if !isSelectionMode {
                onEnterSelectionMode(pic)
            }
        }
        .contextMenu(isSelectionMode ? nil : ContextMenu {
            MediaItemContextMenu(
                item: pic,
                canManage: manager.canManageItem(pic),
                onEnterSelectionMode: onEnterSelectionMode,
                onRequestRename: onRequestRename,
                onRequestMove: onRequestMove,
                onRequestDelete: onRequestDelete,
                onRequestSaveToPhotos: onRequestSaveToPhotos,
                onRequestDownloadToFiles: onRequestDownloadToFiles,
                onInvalidateThumbnail: { item in
                    await manager.invalidateThumbnail(for: item)
                }
            )
        })
    }

    // MARK: - Empty State

    private var emptyPicturesPlaceholder: some View {
        ContentUnavailableView(
            String(localized: .Strings.galleryNoPicturesTitle),
            systemImage: "photo",
            description: Text(.Strings.galleryNoPicturesDescription)
        )
        .padding(.top, 24)
    }
}
