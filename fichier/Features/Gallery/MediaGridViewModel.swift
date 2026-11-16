//
//  MediaGridViewModel.swift
//  fichier
//

import Foundation
import Observation
import SwiftUI
import FichierKit

/// ViewModel managing search, filtering, sorting, selection, batch operations,
/// and file management state for ``MediaGridView``.
@Observable
@MainActor
final class MediaGridViewModel {
    // MARK: - Dependencies

    let manager: StorageLocationManager

    // MARK: - Search & Filter State

    var searchText = ""
    var showFavoritesOnly = false
    var mediaFilter: MediaFilter = .all

    // MARK: - Selection & Batch Processing State

    var isSelectionMode = false
    var selectedItems: Set<MediaItem> = []
    var isBatchProcessing = false
    var batchProgressMessage: String?
    var batchStatusToast: String?
    var batchTask: Task<Void, Never>?
    var shareSheetItems: [Any]?

    // MARK: - Sheet & File Management State

    var showingSettings = false
    var isShowingNewFolderAlert = false
    var newFolderName = ""
    var itemToRename: MediaItem?
    var renameText = ""
    var itemsPendingMove: [MediaItem]?
    var itemsPendingDelete: [MediaItem]?
    var itemsPendingFileExport: [URL]?
    var fileOpErrorMessage: String?
    var thumbnailReloadToken = UUID()

    // MARK: - Initialization

    init(manager: StorageLocationManager) {
        self.manager = manager
    }

    // MARK: - Directory Identification

    var currentDirectoryID: String {
        manager.selectedFolder?.id ?? "root"
    }

    var parentFolderAccessibilityLabel: String {
        if let parentName = manager.parentFolder?.name {
            String(localized: "Navigate to parent folder: \(parentName)", comment: "Accessibility label for parent folder button")
        } else {
            String(localized: "Parent folder", comment: "Accessibility label for parent folder button")
        }
    }

    // MARK: - Filtered and Sorted Data Pipeline

    func filterAndSortData(sortOption: SortOption) -> (folders: [MediaItem], pictures: [MediaItem]) {
        let listFolders = searchText.isEmpty ? manager.currentFolders : manager.currentFolders.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        let sortedFolders = sortItems(listFolders, by: sortOption)

        var listPictures = searchText.isEmpty ? manager.pictures : manager.pictures.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        if showFavoritesOnly {
            listPictures = listPictures.filter { FavoritesManager.shared.isFavorite($0) }
        }
        switch mediaFilter {
        case .all:
            break
        case .photos:
            listPictures = listPictures.filter(\.isImage)
        case .videos:
            listPictures = listPictures.filter { $0.isVideo }
        #if !os(tvOS)
        case .documents:
            listPictures = listPictures.filter { $0.isPDF }
        #endif
        }
        let sortedPictures = sortItems(listPictures, by: sortOption)
        return (sortedFolders, sortedPictures)
    }

    func mediaSectionHeader(for count: Int) -> LocalizedStringResource {
        switch mediaFilter {
        case .all: return .Strings.gallerySectionMediaCount(count)
        case .photos: return .Strings.gallerySectionPhotosCount(count)
        case .videos: return .Strings.gallerySectionVideosCount(count)
        #if !os(tvOS)
        case .documents: return LocalizedStringResource("gallery_section_documents_count", defaultValue: "\(count) Documents")
        #endif
        }
    }

    func sortItems(_ items: [MediaItem], by sortOption: SortOption) -> [MediaItem] {
        switch sortOption {
        case .nameAsc:
            return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .dateDesc:
            return items.sorted { ($0.modifiedDate ?? .distantPast) > ($1.modifiedDate ?? .distantPast) }
        case .dateAsc:
            return items.sorted { ($0.modifiedDate ?? .distantPast) < ($1.modifiedDate ?? .distantPast) }
        case .sizeDesc:
            return items.sorted { $0.size > $1.size }
        case .sizeAsc:
            return items.sorted { $0.size < $1.size }
        }
    }
}
