//
//  MediaListModeView.swift
//  fichier
//

import SwiftUI

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
        onRefresh: @escaping () async -> Void
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
                                        if let d = subfolder.formattedDate {
                                            Text(d)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
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
                        }
                    }
                    .id(folders.isEmpty ? "topOfList" : "picturesSection")
                }
            }
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
