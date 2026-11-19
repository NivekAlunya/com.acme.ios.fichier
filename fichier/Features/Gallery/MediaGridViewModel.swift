//
//  MediaGridViewModel.swift
//  fichier
//

import Foundation
import Observation
import SwiftUI
import Wappn
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
            String(localized: .Strings.galleryNavigateParentFolder(parentName))
        } else {
            String(localized: .Strings.galleryParentFolder)
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

    // MARK: - Batch Selection Actions

    /// Toggles the selection status of a single media item, triggering light haptic feedback.
    func toggleSelection(for item: MediaItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
        AppHapticFeedback.light()
    }

    /// Selects all visible media items if not already all selected; otherwise, clears the selection set.
    func toggleAllSelection(for pictures: [MediaItem]) {
        if selectedItems.count == pictures.count && !pictures.isEmpty {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(pictures)
        }
        AppHapticFeedback.medium()
    }

    /// Toggles the favorite status across all selected items.
    func batchToggleFavorites() {
        let items = Array(selectedItems)
        guard !items.isEmpty else { return }
        let allAreFavs = items.allSatisfy { FavoritesManager.shared.isFavorite($0) }
        for item in items {
            if allAreFavs {
                if FavoritesManager.shared.isFavorite(item) {
                    FavoritesManager.shared.toggleFavorite(item)
                }
            } else {
                if !FavoritesManager.shared.isFavorite(item) {
                    FavoritesManager.shared.toggleFavorite(item)
                }
            }
        }
        AppHapticFeedback.medium()
    }

    /// Cancels any currently active batch save or batch share operation and resets progress flags.
    func cancelBatchTask() {
        batchTask?.cancel()
        batchTask = nil
        isBatchProcessing = false
        batchProgressMessage = nil
    }

    // MARK: - Batch Export to Photos

    /// Exports selected media files to the user's Photos library concurrently using a bounded worker pool.
    func batchSaveToPhotos() {
        let items = Array(selectedItems)
        guard !items.isEmpty else { return }
        isBatchProcessing = true
        batchTask?.cancel()

        batchTask = Task { @MainActor in
            var completedCount = 0
            var savedCount = 0
            var failedCount = 0
            let total = items.count

            if total == 1, let item = items.first {
                batchProgressMessage = String(localized: .Strings.galleryDownloadStartingItem(item.name))
                let throttler = DownloadProgressThrottler()
                let success = await Self.saveSingleMediaItemToPhotos(item, manager: manager) { bytes, totalBytes in
                    Task {
                        guard await throttler.shouldReport(bytes: bytes, total: totalBytes) else { return }
                        await MainActor.run {
                            guard totalBytes > 0 else { return }
                            let readStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                            let totalStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                            let percent = (Double(bytes) / Double(totalBytes)).formatted(.percent.precision(.fractionLength(0)))
                            self.batchProgressMessage = String(localized: .Strings.galleryDownloadProgressBytes(readStr, totalStr, percent))
                        }
                    }
                }
                completedCount = 1
                if success {
                    savedCount = 1
                } else {
                    failedCount = 1
                }
            } else {
                await withTaskGroup(of: Bool.self) { group in
                    var iterator = items.makeIterator()
                    let maxConcurrent = 3

                    for _ in 0..<min(maxConcurrent, total) {
                        if let nextItem = iterator.next() {
                            group.addTask { [manager = self.manager] in
                                await Self.saveSingleMediaItemToPhotos(nextItem, manager: manager)
                            }
                        }
                    }

                    while let success = await group.next() {
                        guard !Task.isCancelled else { break }
                        completedCount += 1
                        if success {
                            savedCount += 1
                        } else {
                            failedCount += 1
                        }
                        batchProgressMessage = String(localized: .Strings.galleryBatchSavingToPhotos(completedCount, total))

                        if let nextItem = iterator.next() {
                            group.addTask { [manager = self.manager] in
                                await Self.saveSingleMediaItemToPhotos(nextItem, manager: manager)
                            }
                        }
                    }
                }
            }

            guard !Task.isCancelled else {
                isBatchProcessing = false
                batchProgressMessage = nil
                return
            }

            isBatchProcessing = false
            batchProgressMessage = nil

            withAnimation {
                if failedCount > 0 && savedCount > 0 {
                    batchStatusToast = String(localized: .Strings.gallerySavedToPhotosPartial(savedCount, total))
                } else if failedCount > 0 && savedCount == 0 {
                    batchStatusToast = String(localized: .Strings.gallerySavedToPhotosFailed)
                } else {
                    batchStatusToast = savedCount == 1
                        ? String(localized: .Strings.gallerySavedToPhotosSingle)
                        : String(localized: .Strings.gallerySavedToPhotosMultiple(savedCount))
                }
                isSelectionMode = false
                selectedItems.removeAll()
            }

            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation {
                batchStatusToast = nil
            }
        }
    }

    /// Saves an individual media item (image or video) to the system Photos library.
    static func saveSingleMediaItemToPhotos(
        _ item: MediaItem,
        manager: StorageLocationManager,
        progress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async -> Bool {
        do {
            if item.isVideo {
                let localURL = try await manager.fetchVideoURL(for: item, progress: progress)
                #if !os(tvOS)
                try await PhotoLibrarySaver.saveVideoToPhotos(at: localURL)
                #endif
            } else {
                if let progress {
                    let localURL = try await manager.downloadItemToFile(for: item, progress: progress)
                    guard let image = UIImage(contentsOfFile: localURL.path) else {
                        return false
                    }
                    #if !os(tvOS)
                    try await PhotoLibrarySaver.saveImageToPhotos(image)
                    #endif
                } else {
                    guard let image = await manager.downloadImage(for: item) else {
                        return false
                    }
                    #if !os(tvOS)
                    try await PhotoLibrarySaver.saveImageToPhotos(image)
                    #endif
                }
            }
            return true
        } catch {
            loge("Failed to save \(item.name): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Batch Download to Files

    /// Downloads selected media items directly to local files and prepares them for file export.
    func batchDownloadToFiles() {
        let items = Array(selectedItems)
        guard !items.isEmpty else { return }
        isBatchProcessing = true
        batchTask?.cancel()

        batchTask = Task { @MainActor in
            var downloadedURLs: [URL] = []
            let total = items.count

            if total == 1, let item = items.first {
                batchProgressMessage = String(localized: .Strings.galleryDownloadStartingItem(item.name))
                let throttler = DownloadProgressThrottler()
                do {
                    let url = try await manager.downloadItemToFile(for: item) { bytes, totalBytes in
                        Task {
                            guard await throttler.shouldReport(bytes: bytes, total: totalBytes) else { return }
                            await MainActor.run {
                                guard totalBytes > 0 else { return }
                                let readStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                                let totalStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                                let percent = (Double(bytes) / Double(totalBytes)).formatted(.percent.precision(.fractionLength(0)))
                                self.batchProgressMessage = String(localized: .Strings.galleryDownloadProgressBytes(readStr, totalStr, percent))
                            }
                        }
                    }
                    downloadedURLs.append(url)
                } catch {
                    loge("Failed to download \(item.name) to file: \(error.localizedDescription)")
                }
            } else {
                for (index, item) in items.enumerated() {
                    guard !Task.isCancelled else { break }
                    batchProgressMessage = String(localized: .Strings.galleryDownloadBatchItemTitle(index + 1, total, item.name))
                    let throttler = DownloadProgressThrottler()
                    do {
                        let url = try await manager.downloadItemToFile(for: item) { bytes, totalBytes in
                            Task {
                                guard await throttler.shouldReport(bytes: bytes, total: totalBytes) else { return }
                                await MainActor.run {
                                    guard totalBytes > 0 else { return }
                                    let readStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                                    let totalStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                                    let percent = (Double(bytes) / Double(totalBytes)).formatted(.percent.precision(.fractionLength(0)))
                                    self.batchProgressMessage = String(localized: .Strings.galleryDownloadBatchItemDetail(index + 1, total, item.name, readStr, totalStr, percent))
                                }
                            }
                        }
                        downloadedURLs.append(url)
                    } catch {
                        loge("Failed to download \(item.name) to file: \(error.localizedDescription)")
                    }
                }
            }

            guard !Task.isCancelled else {
                isBatchProcessing = false
                batchProgressMessage = nil
                return
            }

            isBatchProcessing = false
            batchProgressMessage = nil

            if downloadedURLs.isEmpty {
                withAnimation {
                    batchStatusToast = String(localized: .Strings.galleryBatchDownloadFailed)
                }
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation {
                    batchStatusToast = nil
                }
            } else {
                #if !os(tvOS)
                itemsPendingFileExport = downloadedURLs
                #else
                withAnimation {
                    batchStatusToast = String(localized: .Strings.galleryBatchDownloadedCount(downloadedURLs.count))
                }
                #endif
            }
        }
    }

    // MARK: - Batch Share Preparation

    /// Prepares selected media items for the system share sheet concurrently while strictly preserving selection order.
    func batchShare() {
        let items = Array(selectedItems)
        guard !items.isEmpty else { return }
        isBatchProcessing = true
        batchProgressMessage = String(localized: .Strings.galleryBatchPreparingShare)
        batchTask?.cancel()

        batchTask = Task { @MainActor in
            var shareables: [Any] = []
            let total = items.count
            var completedCount = 0

            await withTaskGroup(of: (Int, (any Sendable)?).self) { group in
                let itemQueue = Array(items.enumerated())
                var queueIndex = 0
                let maxConcurrent = 3

                for _ in 0..<min(maxConcurrent, total) where queueIndex < itemQueue.count {
                    let (idx, item) = itemQueue[queueIndex]
                    queueIndex += 1
                    group.addTask { [manager = self.manager] in
                        let result = await Self.prepareSingleItemForShare(item, manager: manager)
                        return (idx, result)
                    }
                }

                var indexedResults: [(Int, any Sendable)] = []
                while let (idx, result) = await group.next() {
                    guard !Task.isCancelled else { break }
                    completedCount += 1
                    batchProgressMessage = "\(String(localized: .Strings.galleryBatchPreparingShare)) (\(completedCount)/\(total))"

                    if let result {
                        indexedResults.append((idx, result))
                    }

                    if queueIndex < itemQueue.count {
                        let (nextIdx, nextItem) = itemQueue[queueIndex]
                        queueIndex += 1
                        group.addTask { [manager = self.manager] in
                            let nextResult = await Self.prepareSingleItemForShare(nextItem, manager: manager)
                            return (nextIdx, nextResult)
                        }
                    }
                }

                indexedResults.sort { $0.0 < $1.0 }
                shareables = indexedResults.map { $0.1 as Any }
            }

            guard !Task.isCancelled else {
                isBatchProcessing = false
                batchProgressMessage = nil
                return
            }

            isBatchProcessing = false
            batchProgressMessage = nil

            if !shareables.isEmpty {
                shareSheetItems = shareables
            }
        }
    }

    /// Prepares an individual media item for sharing by downloading its image or fetching its local video URL.
    static func prepareSingleItemForShare(_ item: MediaItem, manager: StorageLocationManager) async -> (any Sendable)? {
        if item.isVideo {
            return try? await manager.fetchVideoURL(for: item)
        } else {
            return await manager.downloadImage(for: item)
        }
    }

    // MARK: - File Management Operations

    /// Indicates whether the currently pending delete batch targets items on an SMB network share.
    var isDeletingFromSMB: Bool {
        itemsPendingDelete?.contains(where: { $0.localURL == nil && !$0.shareName.isEmpty }) ?? false
    }

    /// Title presented inside the trash deletion confirmation dialog.
    var deleteConfirmationTitle: String {
        guard let items = itemsPendingDelete, !items.isEmpty else { return "" }
        if isDeletingFromSMB {
            if items.count == 1, let first = items.first {
                return String(localized: .Strings.galleryConfirmDeleteSinglePermanentTitle(first.name))
            }
            return String(localized: .Strings.galleryConfirmDeleteMultiplePermanentTitle(items.count))
        } else {
            if items.count == 1, let first = items.first {
                return String(localized: .Strings.galleryConfirmMoveSingleToTrashTitle(first.name))
            }
            return String(localized: .Strings.galleryConfirmMoveMultipleToTrashTitle(items.count))
        }
    }

    /// Button title for confirming deletion.
    var deleteConfirmationButtonTitle: String {
        if isDeletingFromSMB {
            return String(localized: .Strings.galleryActionDeletePermanently)
        } else {
            return String(localized: .Strings.galleryActionMoveToTrash)
        }
    }

    /// Message explaining the permanent or trash nature of the pending delete.
    var deleteConfirmationMessage: String {
        if isDeletingFromSMB {
            return String(localized: .Strings.galleryWarningPermanentDeleteSmb)
        } else {
            return String(localized: .Strings.galleryInfoMoveToTrash)
        }
    }

    /// Executes deletion across selected or targeted items.
    func executeDelete(items: [MediaItem]) async {
        do {
            let wasSMB = items.contains(where: { $0.localURL == nil && !$0.shareName.isEmpty })
            try await manager.deleteItems(items)
            if isSelectionMode {
                withAnimation {
                    isSelectionMode = false
                    selectedItems.removeAll()
                }
            }
            if wasSMB {
                showToastMessage(items.count == 1 ? String(localized: .Strings.galleryToastSingleItemPermanentlyDeleted) : String(localized: .Strings.galleryToastMultipleItemsPermanentlyDeleted(items.count)))
            } else {
                showToastMessage(items.count == 1 ? String(localized: .Strings.galleryToastSingleItemMovedToTrash) : String(localized: .Strings.galleryToastMultipleItemsMovedToTrash(items.count)))
            }
        } catch {
            fileOpErrorMessage = error.localizedDescription
        }
    }

    /// Dispatches moving items to the selected destination folder.
    func executeMove(items: [MediaItem], to destination: MediaItem) {
        Task {
            do {
                try await manager.moveItems(items, to: destination)
                if isSelectionMode {
                    withAnimation {
                        isSelectionMode = false
                        selectedItems.removeAll()
                    }
                }
                let destName = destination.name.isEmpty ? destination.rootName : destination.name
                showToastMessage(items.count == 1 ? String(localized: .Strings.galleryToastSingleItemMoved(destName)) : String(localized: .Strings.galleryToastMultipleItemsMoved(items.count, destName)))
            } catch {
                fileOpErrorMessage = error.localizedDescription
            }
        }
    }

    /// Creates a new directory inside the current folder.
    func executeCreateFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                try await manager.createFolder(named: trimmed)
                showToastMessage(String(localized: .Strings.galleryToastFolderCreated(trimmed)))
            } catch {
                fileOpErrorMessage = error.localizedDescription
            }
        }
    }

    /// Renames a file or folder and updates selection and toast notification.
    func executeRename(item: MediaItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                let renamed = try await manager.renameItem(item, to: trimmed)
                if isSelectionMode {
                    withAnimation {
                        selectedItems.remove(item)
                        selectedItems.insert(renamed)
                    }
                }
                showToastMessage(
                    item.isDirectory
                        ? String(localized: .Strings.galleryToastFolderRenamed(renamed.name))
                        : String(localized: .Strings.galleryToastFileRenamed(renamed.name))
                )
            } catch {
                fileOpErrorMessage = error.localizedDescription
            }
        }
    }

    /// Displays a transient animated notification pill at the top of the gallery.
    func showToastMessage(_ message: String) {
        withAnimation {
            batchStatusToast = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation {
                batchStatusToast = nil
            }
        }
    }
}
