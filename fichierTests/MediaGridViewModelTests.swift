//
//  MediaGridViewModelTests.swift
//  fichierTests
//

import Foundation
import Testing
import FichierKit
@testable import fichier

@Suite("MediaGridViewModel")
@MainActor
struct MediaGridViewModelTests {
    private func makeItem(
        name: String,
        isDirectory: Bool = false,
        size: Int64 = 0,
        modifiedDate: Date? = nil
    ) -> MediaItem {
        MediaItem(
            name: name,
            path: "/\(name)",
            isDirectory: isDirectory,
            size: size,
            modifiedDate: modifiedDate
        )
    }

    @Test("sortItems orders by name, size, and date")
    func sortItemsOrdering() {
        let viewModel = MediaGridViewModel(manager: StorageLocationManager())
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let items = [
            makeItem(name: "File 10.jpg", size: 300, modifiedDate: older),
            makeItem(name: "File 2.jpg", size: 100, modifiedDate: newer)
        ]

        #expect(viewModel.sortItems(items, by: .nameAsc).map(\.name) == ["File 2.jpg", "File 10.jpg"])
        #expect(viewModel.sortItems(items, by: .nameDesc).map(\.name) == ["File 10.jpg", "File 2.jpg"])
        #expect(viewModel.sortItems(items, by: .sizeAsc).map(\.name) == ["File 2.jpg", "File 10.jpg"])
        #expect(viewModel.sortItems(items, by: .sizeDesc).map(\.name) == ["File 10.jpg", "File 2.jpg"])
        #expect(viewModel.sortItems(items, by: .dateAsc).map(\.name) == ["File 10.jpg", "File 2.jpg"])
        #expect(viewModel.sortItems(items, by: .dateDesc).map(\.name) == ["File 2.jpg", "File 10.jpg"])
    }

    @Test("filterAndSortData filters folders and pictures by searchText and mediaFilter")
    func filterAndSortData() {
        let manager = StorageLocationManager()
        manager.currentFolders = [
            makeItem(name: "Vacation", isDirectory: true),
            makeItem(name: "Work", isDirectory: true)
        ]
        manager.pictures = [
            makeItem(name: "beach.jpg", size: 10),
            makeItem(name: "clip.mp4", size: 20),
            makeItem(name: "notes.pdf", size: 30)
        ]

        let viewModel = MediaGridViewModel(manager: manager)

        let all = viewModel.filterAndSortData(sortOption: .nameAsc)
        #expect(all.folders.map(\.name) == ["Vacation", "Work"])
        #expect(all.pictures.map(\.name) == ["beach.jpg", "clip.mp4", "notes.pdf"])

        viewModel.mediaFilter = .photos
        #expect(viewModel.filterAndSortData(sortOption: .nameAsc).pictures.map(\.name) == ["beach.jpg"])

        viewModel.mediaFilter = .videos
        #expect(viewModel.filterAndSortData(sortOption: .nameAsc).pictures.map(\.name) == ["clip.mp4"])

        viewModel.mediaFilter = .documents
        #expect(viewModel.filterAndSortData(sortOption: .nameAsc).pictures.map(\.name) == ["notes.pdf"])

        viewModel.mediaFilter = .all
        viewModel.searchText = "vac"
        let searched = viewModel.filterAndSortData(sortOption: .nameAsc)
        #expect(searched.folders.map(\.name) == ["Vacation"])
        #expect(searched.pictures.isEmpty)
    }

    @Test("requestDownloadConfirmation ignores empty items and stores pending confirmation")
    func requestDownloadConfirmationState() {
        let viewModel = MediaGridViewModel(manager: StorageLocationManager())

        viewModel.requestDownloadConfirmation(items: [], kind: .downloadToFiles)
        #expect(viewModel.pendingDownloadConfirmation == nil)

        let items = [makeItem(name: "photo.jpg"), makeItem(name: "clip.mp4")]
        viewModel.requestDownloadConfirmation(items: items, kind: .saveToPhotos)
        #expect(viewModel.pendingDownloadConfirmation == PendingDownloadConfirmation(items: items, kind: .saveToPhotos))

        viewModel.requestDownloadConfirmation(items: [items[0]], kind: .downloadToFiles)
        #expect(viewModel.pendingDownloadConfirmation == PendingDownloadConfirmation(items: [items[0]], kind: .downloadToFiles))
    }

    @Test("executePendingDownload clears pending confirmation and starts batch task")
    func executePendingDownloadClearsAndStartsTask() {
        let viewModel = MediaGridViewModel(manager: StorageLocationManager())
        let items = [makeItem(name: "photo.jpg"), makeItem(name: "notes.pdf")]

        viewModel.executePendingDownload()
        #expect(viewModel.pendingDownloadConfirmation == nil)
        #expect(!viewModel.isBatchProcessing)

        viewModel.requestDownloadConfirmation(items: items, kind: .downloadToFiles)
        viewModel.executePendingDownload()

        #expect(viewModel.pendingDownloadConfirmation == nil)
        #expect(viewModel.isBatchProcessing)
        viewModel.cancelBatchTask()
        #expect(!viewModel.isBatchProcessing)
    }
}
