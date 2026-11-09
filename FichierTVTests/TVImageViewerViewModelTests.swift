//
//  TVImageViewerViewModelTests.swift
//  FichierTVTests
//
//

import Foundation
import Testing
@testable import FichierTV
import FichierKit

@Suite("TVImageViewerViewModel Tests")
struct TVImageViewerViewModelTests {
    @Test("Filters non-image items from browser context and navigates")
    @MainActor
    func testFilteringAndNavigation() {
        let folder = MediaSourceItem(id: "f1", name: "Folder", path: "f1", type: .folder)
        let img1 = MediaSourceItem(id: "i1", name: "Photo1.jpg", path: "i1", type: .image)
        let vid = MediaSourceItem(id: "v1", name: "Clip.mov", path: "v1", type: .video)
        let img2 = MediaSourceItem(id: "i2", name: "Photo2.jpg", path: "i2", type: .image)

        let viewModel = TVImageViewerViewModel(
            initialItem: img1,
            items: [folder, img1, vid, img2],
            settingsStore: StubSlideshowSettingsStore(),
            resolver: StubMediaSourceResolver()
        )

        #expect(viewModel.items.count == 2)
        #expect(viewModel.currentIndex == 0)
        #expect(!viewModel.canNavigatePrevious)
        #expect(viewModel.canNavigateNext)

        viewModel.showNext()
        #expect(viewModel.currentIndex == 1)
        #expect(viewModel.currentItem.id == "i2")
        #expect(viewModel.canNavigatePrevious)
        #expect(!viewModel.canNavigateNext)
        #expect(viewModel.transitionDirection == .forward)

        viewModel.showPrevious()
        #expect(viewModel.currentIndex == 0)
        #expect(viewModel.transitionDirection == .backward)

        viewModel.tearDown()
    }

    @Test("Loads and persists slideshow settings and wraparound state")
    @MainActor
    func testSlideshowSettingsAndToggle() async {
        let settingsStore = StubSlideshowSettingsStore(interval: 8.0, style: .fade)
        let img1 = MediaSourceItem(id: "i1", name: "1.jpg", path: "1", type: .image)
        let img2 = MediaSourceItem(id: "i2", name: "2.jpg", path: "2", type: .image)

        let viewModel = TVImageViewerViewModel(
            initialItem: img2,
            items: [img1, img2],
            settingsStore: settingsStore,
            resolver: StubMediaSourceResolver()
        )

        await viewModel.loadSettings()
        #expect(viewModel.slideshowInterval == 8.0)
        #expect(viewModel.transitionStyle == .fade)

        viewModel.startSlideshow()
        #expect(viewModel.isSlideshowPlaying)
        #expect(!viewModel.showOverlay)

        // Reaching end during active slideshow wraps back to index 0
        viewModel.showNext()
        #expect(viewModel.currentIndex == 0)

        viewModel.stopSlideshow()
        #expect(!viewModel.isSlideshowPlaying)
        viewModel.tearDown()
    }

    @Test("Excludes video file extensions even if item type is reported as image")
    @MainActor
    func testExcludesVideoExtensionEvenIfLabeledAsImage() {
        let mislabeledVideo = MediaSourceItem(id: "v-bad", name: "Holiday.mkv", path: "Holiday.mkv", type: .image)
        let img1 = MediaSourceItem(id: "i1", name: "IMG_001.jpg", path: "IMG_001.jpg", type: .image)
        let realVideo = MediaSourceItem(id: "v1", name: "VID_002.mov", path: "VID_002.mov", type: .video)
        let img2 = MediaSourceItem(id: "i2", name: "IMG_003.heic", path: "IMG_003.heic", type: .image)

        let viewModel = TVImageViewerViewModel(
            initialItem: img1,
            items: [mislabeledVideo, img1, realVideo, img2],
            settingsStore: StubSlideshowSettingsStore(),
            resolver: StubMediaSourceResolver()
        )

        #expect(viewModel.items.map(\.id) == ["i1", "i2"])
        #expect(viewModel.currentItem.id == "i1")
        viewModel.showNext()
        #expect(viewModel.currentItem.id == "i2")
        #expect(!viewModel.canNavigateNext)
        viewModel.tearDown()
    }

    @Test("Paginates across source pages and skips video-only pages without stopping early")
    @MainActor
    func testMultiPagePaginationSkipsVideoOnlyPages() async {
        let allItems: [MediaSourceItem] = [
            // Page 0 (pageSize = 4)
            MediaSourceItem(id: "p0-1", name: "01_photo.jpg", path: "01_photo.jpg", type: .image),
            MediaSourceItem(id: "p0-2", name: "02_clip.mov", path: "02_clip.mov", type: .video),
            MediaSourceItem(id: "p0-3", name: "03_photo.jpg", path: "03_photo.jpg", type: .image),
            MediaSourceItem(id: "p0-4", name: "04_clip.mp4", path: "04_clip.mp4", type: .video),
            // Page 1 (all videos)
            MediaSourceItem(id: "p1-1", name: "05_movie.mkv", path: "05_movie.mkv", type: .video),
            MediaSourceItem(id: "p1-2", name: "06_movie.avi", path: "06_movie.avi", type: .video),
            MediaSourceItem(id: "p1-3", name: "07_movie.webm", path: "07_movie.webm", type: .video),
            MediaSourceItem(id: "p1-4", name: "08_movie.mov", path: "08_movie.mov", type: .video),
            // Page 2 (final partial page with more photos)
            MediaSourceItem(id: "p2-1", name: "09_movie.mov", path: "09_movie.mov", type: .video),
            MediaSourceItem(id: "p2-2", name: "10_photo.jpg", path: "10_photo.jpg", type: .image),
            MediaSourceItem(id: "p2-3", name: "11_photo.heic", path: "11_photo.heic", type: .image)
        ]

        let source = StubMediaSource(id: "smb-photos", items: allItems)
        let resolver = StubMediaSourceResolver(sources: [source.id: source])
        let pagination = TVViewerPaginationContext(
            sourceID: source.id,
            folder: nil,
            sortKey: .name,
            sortOrder: .ascending,
            nextPage: 1,
            canLoadMore: true,
            pageSize: 4
        )

        let viewModel = TVImageViewerViewModel(
            initialItem: allItems[0],
            items: Array(allItems[0..<4]),
            paginationContext: pagination,
            settingsStore: StubSlideshowSettingsStore(),
            resolver: resolver
        )
        defer { viewModel.tearDown() }

        #expect(viewModel.items.map(\.name) == ["01_photo.jpg", "03_photo.jpg"])
        #expect(viewModel.canNavigateNext)

        await viewModel.prefetchRemainingImagesIfNeeded()

        #expect(viewModel.items.map(\.name) == ["01_photo.jpg", "03_photo.jpg", "10_photo.jpg", "11_photo.heic"])
        #expect(viewModel.canNavigateNext)

        viewModel.showNext()
        #expect(viewModel.currentItem.name == "03_photo.jpg")
        #expect(viewModel.canNavigateNext)

        viewModel.showNext()
        #expect(viewModel.currentItem.name == "10_photo.jpg")
        #expect(viewModel.canNavigateNext)

        viewModel.showNext()
        #expect(viewModel.currentItem.name == "11_photo.heic")
        #expect(!viewModel.canNavigateNext)
    }

    @Test("Clicking Next at page boundary fetches remaining pages and advances onto next photo")
    @MainActor
    func testShowNextAtBoundaryLoadsMoreAndAdvances() async {
        let allItems: [MediaSourceItem] = [
            MediaSourceItem(id: "i1", name: "01.jpg", path: "01.jpg", type: .image),
            MediaSourceItem(id: "v1", name: "02.mov", path: "02.mov", type: .video),
            MediaSourceItem(id: "v2", name: "03.mp4", path: "03.mp4", type: .video),
            MediaSourceItem(id: "v3", name: "04.mkv", path: "04.mkv", type: .video),
            MediaSourceItem(id: "i2", name: "05.jpg", path: "05.jpg", type: .image)
        ]

        let source = StubMediaSource(id: "photos-source", items: allItems)
        let resolver = StubMediaSourceResolver(sources: [source.id: source])
        let pagination = TVViewerPaginationContext(
            sourceID: source.id,
            folder: nil,
            sortKey: .name,
            sortOrder: .ascending,
            nextPage: 1,
            canLoadMore: true,
            pageSize: 2
        )

        let viewModel = TVImageViewerViewModel(
            initialItem: allItems[0],
            items: Array(allItems[0..<2]),
            paginationContext: pagination,
            settingsStore: StubSlideshowSettingsStore(),
            resolver: resolver
        )
        defer { viewModel.tearDown() }

        #expect(viewModel.items.count == 1)
        #expect(viewModel.canNavigateNext)

        viewModel.showNext()

        for _ in 0..<40 {
            if viewModel.currentItem.name == "05.jpg" {
                break
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        #expect(viewModel.currentItem.name == "05.jpg")
        #expect(viewModel.items.map(\.name) == ["01.jpg", "05.jpg"])
        #expect(!viewModel.canNavigateNext)
    }

    @Test("Source error during pagination clears hasMoreSourcePages cleanly")
    @MainActor
    func testPaginationErrorClearsCanNavigateNext() async {
        let initialItems = [
            MediaSourceItem(id: "i1", name: "01.jpg", path: "01.jpg", type: .image)
        ]
        let failingSource = StubMediaSource(
            id: "failing-source",
            items: [],
            simulatedError: SMBError.timeout
        )
        let resolver = StubMediaSourceResolver(sources: [failingSource.id: failingSource])
        let pagination = TVViewerPaginationContext(
            sourceID: failingSource.id,
            folder: nil,
            sortKey: .name,
            sortOrder: .ascending,
            nextPage: 1,
            canLoadMore: true,
            pageSize: 40
        )

        let viewModel = TVImageViewerViewModel(
            initialItem: initialItems[0],
            items: initialItems,
            paginationContext: pagination,
            settingsStore: StubSlideshowSettingsStore(),
            resolver: resolver
        )
        defer { viewModel.tearDown() }

        #expect(viewModel.canNavigateNext)
        await viewModel.prefetchRemainingImagesIfNeeded()
        #expect(!viewModel.canNavigateNext)
    }

    @Test("Going Previous cancels pending forward advance from background pagination")
    @MainActor
    func testShowPreviousCancelsPendingAdvance() async {
        let allItems = [
            MediaSourceItem(id: "i1", name: "01.jpg", path: "01.jpg", type: .image),
            MediaSourceItem(id: "i2", name: "02.jpg", path: "02.jpg", type: .image),
            MediaSourceItem(id: "i3", name: "03.jpg", path: "03.jpg", type: .image)
        ]
        let slowSource = StubMediaSource(
            id: "slow-source",
            items: allItems,
            fetchDelayNanoseconds: 100_000_000
        )
        let resolver = StubMediaSourceResolver(sources: [slowSource.id: slowSource])
        let pagination = TVViewerPaginationContext(
            sourceID: slowSource.id,
            folder: nil,
            sortKey: .name,
            sortOrder: .ascending,
            nextPage: 1,
            canLoadMore: true,
            pageSize: 2
        )

        let viewModel = TVImageViewerViewModel(
            initialItem: allItems[1],
            items: Array(allItems[0..<2]),
            paginationContext: pagination,
            settingsStore: StubSlideshowSettingsStore(),
            resolver: resolver
        )
        defer { viewModel.tearDown() }

        viewModel.showNext()
        viewModel.showPrevious()

        await viewModel.prefetchRemainingImagesIfNeeded()
        #expect(viewModel.currentItem.name == "01.jpg")
        #expect(viewModel.items.map(\.name) == ["01.jpg", "02.jpg", "03.jpg"])
    }
}
