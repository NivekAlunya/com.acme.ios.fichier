//
//  MediaGridModeView.swift
//  fichier
//

import SwiftUI

/// Adaptive grid presentation featuring an optional subfolder shelf and a thumbnail matrix.
@MainActor
struct MediaGridModeView: View {
    let manager: StorageLocationManager
    let folders: [MediaItem]
    let pictures: [MediaItem]
    let gridColumns: [GridItem]
    let gridSize: GridSize
    let sortOption: SortOption
    let isSelectionMode: Bool
    let selectedItems: Set<MediaItem>
    let currentDirectoryID: String
    let onNavigateToFolder: (MediaItem) -> Void
    let onSelectPicture: (MediaItem, [MediaItem]) -> Void
    let onToggleSelection: (MediaItem) -> Void
    let onEnterSelectionMode: (MediaItem) -> Void
    let onRefresh: () async -> Void
    
    init(
        manager: StorageLocationManager,
        folders: [MediaItem],
        pictures: [MediaItem],
        gridColumns: [GridItem],
        gridSize: GridSize,
        sortOption: SortOption,
        isSelectionMode: Bool,
        selectedItems: Set<MediaItem>,
        currentDirectoryID: String,
        onNavigateToFolder: @escaping (MediaItem) -> Void,
        onSelectPicture: @escaping (MediaItem, [MediaItem]) -> Void,
        onToggleSelection: @escaping (MediaItem) -> Void,
        onEnterSelectionMode: @escaping (MediaItem) -> Void,
        onRefresh: @escaping () async -> Void
    ) {
        self.manager = manager
        self.folders = folders
        self.pictures = pictures
        self.gridColumns = gridColumns
        self.gridSize = gridSize
        self.sortOption = sortOption
        self.isSelectionMode = isSelectionMode
        self.selectedItems = selectedItems
        self.currentDirectoryID = currentDirectoryID
        self.onNavigateToFolder = onNavigateToFolder
        self.onSelectPicture = onSelectPicture
        self.onToggleSelection = onToggleSelection
        self.onEnterSelectionMode = onEnterSelectionMode
        self.onRefresh = onRefresh
    }
    
    private func mediaSectionHeader(for count: Int) -> LocalizedStringResource {
        .Strings.gallerySectionMediaCount(count)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id("topOfGrid")
                
                VStack(alignment: .leading, spacing: 16) {
                    if !folders.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(.Strings.gallerySectionSubfoldersCount(folders.count))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 8)], spacing: 8) {
                                ForEach(folders) { subfolder in
                                    Button {
                                        onNavigateToFolder(subfolder)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "folder.fill")
                                                .foregroundColor(.blue)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(subfolder.name)
                                                    .font(.subheadline)
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)
                                                if let d = subfolder.formattedDate {
                                                    Text(d)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(10)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    
                    if !pictures.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(mediaSectionHeader(for: pictures.count))
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
                                    MediaThumbnailCell(
                                        manager: manager,
                                        item: pic,
                                        maxDimension: gridSize.thumbnailPixels,
                                        isSelected: selectedItems.contains(pic),
                                        isSelectionMode: isSelectionMode
                                    )
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
                                }
                            }
                            .padding(.horizontal, 12)
                            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: gridSize)
                        }
                    } else if !folders.isEmpty && !manager.isLoading {
                        ContentUnavailableView(
                            String(localized: .Strings.galleryNoPicturesTitle),
                            systemImage: "photo",
                            description: Text(.Strings.galleryNoPicturesDescription)
                        )
                        .padding(.top, 24)
                    }
                }
                .padding(.vertical, 12)
            }
            .id(currentDirectoryID)
            .onChange(of: currentDirectoryID) { _, _ in
                proxy.scrollTo("topOfGrid", anchor: .top)
            }
            .onChange(of: manager.isLoading) { wasLoading, isLoading in
                if wasLoading && !isLoading {
                    proxy.scrollTo("topOfGrid", anchor: .top)
                }
            }
            .refreshable {
                await onRefresh()
            }
        }
    }
}
