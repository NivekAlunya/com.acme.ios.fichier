//
//  TVBrowserViewModelTests.swift
//  FichierTVTests
//
//

import Foundation
import Testing
@testable import FichierTV
import FichierKit

@Suite("TVBrowserViewModel Tests")
struct TVBrowserViewModelTests {
    @Test("Loads initial page, restores saved sort preference, and paginates")
    @MainActor
    func testInitialLoadAndPagination() async {
        let items = (0..<55).map { index in
            MediaSourceItem(
                id: "item_\(index)",
                name: String(format: "Item_%02d.jpg", index),
                path: "item_\(index)",
                type: .image,
                modifiedDate: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let source = StubMediaSource(
            id: "photos",
            supportedSortKeys: [.date, .name],
            items: items
        )
        let prefStore = StubSortPreferenceStore(initialPreferences: [
            "photos": MediaSortPreference(key: .name, order: .ascending)
        ])

        let viewModel = TVBrowserViewModel(source: source, folder: nil, preferenceStore: prefStore)
        await viewModel.loadInitial()

        #expect(viewModel.selectedSortKey == .name)
        #expect(viewModel.selectedSortOrder == .ascending)
        #expect(viewModel.items.count == 40)
        #expect(viewModel.canLoadMore)
        #expect(viewModel.firstItemID == "item_0")

        await viewModel.loadNextPage()
        #expect(viewModel.items.count == 55)
        #expect(!viewModel.canLoadMore)
    }

    @Test("Captures fetch error when source throws")
    @MainActor
    func testErrorHandling() async {
        let expectedError = NSError(domain: "TestError", code: 42, userInfo: [NSLocalizedDescriptionKey: "Network unreachable"])
        let source = StubMediaSource(id: "shares", simulatedError: expectedError)
        let prefStore = StubSortPreferenceStore()

        let viewModel = TVBrowserViewModel(source: source, folder: nil, preferenceStore: prefStore)
        await viewModel.loadInitial()

        #expect(viewModel.items.isEmpty)
        #expect(!viewModel.isLoading)
        #expect(viewModel.errorMessage == "Network unreachable")
    }

    @Test("Defaults sort to filename ascending even when date sort is supported")
    @MainActor
    func testDefaultSortIsFilenameAscending() async {
        let items = [
            MediaSourceItem(
                id: "item10",
                name: "Clip 10.mp4",
                path: "clip10.mp4",
                type: .video,
                modifiedDate: Date(timeIntervalSince1970: 500)
            ),
            MediaSourceItem(
                id: "item2",
                name: "Clip 2.mp4",
                path: "clip2.mp4",
                type: .video,
                modifiedDate: Date(timeIntervalSince1970: 100)
            )
        ]
        let photosStub = StubMediaSource(id: "photos", supportedSortKeys: [.date, .name], items: items)
        let smbStub = StubMediaSource(
            id: "smb://server",
            preferredLayout: .list,
            supportedSortKeys: [.name, .date, .size, .type],
            items: items
        )

        let photosVM = TVBrowserViewModel(source: photosStub, folder: nil, preferenceStore: StubSortPreferenceStore())
        #expect(photosVM.selectedSortKey == .name)
        #expect(photosVM.selectedSortOrder == .ascending)
        await photosVM.loadInitial()
        #expect(photosVM.items.map(\.name) == ["Clip 2.mp4", "Clip 10.mp4"])

        let smbVM = TVBrowserViewModel(source: smbStub, folder: nil, preferenceStore: StubSortPreferenceStore())
        #expect(smbVM.selectedSortKey == .name)
        #expect(smbVM.selectedSortOrder == .ascending)
        await smbVM.loadInitial()
        #expect(smbVM.items.map(\.name) == ["Clip 2.mp4", "Clip 10.mp4"])
    }

    @Test("Applies sort change and persists preference")
    @MainActor
    func testSortPersistence() async throws {
        let items = [
            MediaSourceItem(id: "b", name: "B.jpg", path: "b", type: .image),
            MediaSourceItem(id: "a", name: "A.jpg", path: "a", type: .image)
        ]
        let source = StubMediaSource(id: "photos", supportedSortKeys: [.date, .name], items: items)
        let prefStore = StubSortPreferenceStore()

        let viewModel = TVBrowserViewModel(source: source, folder: nil, preferenceStore: prefStore)
        await viewModel.loadInitial()
        #expect(viewModel.selectedSortKey == .name)
        viewModel.applySort(key: .date)

        // Allow internal preference task to complete
        for _ in 0..<50 {
            if await prefStore.preference(for: "photos")?.key == .date {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let saved = await prefStore.preference(for: "photos")
        #expect(saved?.key == .date)
    }

    @Test("Allows switching list-preferred SMB source to grid and restores persisted layout")
    @MainActor
    func testLayoutToggleAndPersistence() async throws {
        let items = [
            MediaSourceItem(id: "vid1", name: "Clip.mkv", path: "Media/Clip.mkv", type: .video, size: 2048),
            MediaSourceItem(id: "img1", name: "Photo.jpg", path: "Media/Photo.jpg", type: .image, size: 1024)
        ]
        let smbSource = StubMediaSource(
            id: "smb://nas.local",
            displayName: "NAS",
            preferredLayout: .list,
            supportedSortKeys: [.name, .date, .size, .type],
            items: items
        )
        let sortStore = StubSortPreferenceStore()
        let layoutStore = StubLayoutPreferenceStore()

        let viewModel = TVBrowserViewModel(
            source: smbSource,
            folder: nil,
            preferenceStore: sortStore,
            layoutPreferenceStore: layoutStore
        )
        #expect(viewModel.selectedLayout == .list)

        await viewModel.loadInitial()
        #expect(viewModel.items.count == 2)
        #expect(viewModel.selectedLayout == .list)

        viewModel.setLayout(.grid)
        #expect(viewModel.selectedLayout == .grid)
        #expect(viewModel.items.count == 2)

        for _ in 0..<50 {
            if await layoutStore.layout(for: "smb://nas.local") == .grid {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(await layoutStore.layout(for: "smb://nas.local") == .grid)

        // New ViewModel (e.g. entering a subfolder) restores saved .grid layout
        let childViewModel = TVBrowserViewModel(
            source: smbSource,
            folder: items[0],
            preferenceStore: sortStore,
            layoutPreferenceStore: layoutStore
        )
        await childViewModel.loadInitial()
        #expect(childViewModel.selectedLayout == .grid)

        childViewModel.toggleLayout()
        #expect(childViewModel.selectedLayout == .list)

        for _ in 0..<50 {
            if await layoutStore.layout(for: "smb://nas.local") == .list {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await viewModel.refreshSavedLayout()
        #expect(viewModel.selectedLayout == .list)
    }

    @Test("Forced sort reload overrides in-flight initial load without stale results overwriting")
    @MainActor
    func testSortOverridesInFlightInitialLoad() async throws {
        // Note: default sort is .name .ascending:
        // - by .name ascending: Alpha before Zebra -> ["alpha", "zebra"]
        // - by .date ascending: Zebra (100) before Alpha (200) -> ["zebra", "alpha"]
        let items = [
            MediaSourceItem(
                id: "zebra",
                name: "Zebra.mp4",
                path: "zebra",
                type: .video,
                modifiedDate: Date(timeIntervalSince1970: 100)
            ),
            MediaSourceItem(
                id: "alpha",
                name: "Alpha.mp4",
                path: "alpha",
                type: .video,
                modifiedDate: Date(timeIntervalSince1970: 200)
            )
        ]
        let source = StubMediaSource(
            id: "smb://slow.local",
            preferredLayout: .list,
            supportedSortKeys: [.date, .name],
            items: items,
            fetchDelayNanoseconds: 120_000_000
        )
        let sortStore = StubSortPreferenceStore()
        let viewModel = TVBrowserViewModel(source: source, folder: nil, preferenceStore: sortStore)

        let initialTask = Task {
            await viewModel.loadInitial()
        }

        // Wait until first loadInitial is active before applying user sort change
        try await Task.sleep(nanoseconds: 25_000_000)
        viewModel.applySort(key: .date)

        await initialTask.value
        for _ in 0..<40 {
            if !viewModel.isLoading, viewModel.items.first?.id == "zebra" {
                break
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        #expect(viewModel.selectedSortKey == .date)
        #expect(viewModel.items.map(\.id) == ["zebra", "alpha"])
    }

    @Test("Discards stale pagination response after forced reload and resets isPaginating")
    @MainActor
    func testStaleNextPageIgnoredAfterForcedReload() async {
        let items = (0..<60).map { index in
            MediaSourceItem(
                id: "item_\(index)",
                name: String(format: "Item_%02d.jpg", index),
                path: "item_\(index)",
                type: .image,
                modifiedDate: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let source = GatedStubMediaSource(id: "photos", items: items)
        let viewModel = TVBrowserViewModel(
            source: source,
            folder: nil,
            preferenceStore: StubSortPreferenceStore(),
            layoutPreferenceStore: StubLayoutPreferenceStore()
        )

        await viewModel.loadInitial()
        #expect(viewModel.items.count == 40)
        #expect(!viewModel.isPaginating)

        await source.armGate(forPage: 1)
        let stalePageTask = Task {
            await viewModel.loadNextPage()
        }
        await source.waitUntilGatedFetchStarts()
        #expect(viewModel.isPaginating)

        await viewModel.loadInitial(force: true)
        #expect(!viewModel.isLoading)
        #expect(!viewModel.isPaginating)

        await source.releaseGate()
        await stalePageTask.value

        #expect(viewModel.items.count == 40)
        #expect(viewModel.paginationContext.nextPage == 1)
        #expect(viewModel.canLoadMore)
        #expect(!viewModel.isPaginating)
    }

    @Test("Discards stale pagination response after sort change and keeps new sort items")
    @MainActor
    func testStaleNextPageIgnoredAfterSortChange() async throws {
        let primaryItems = (0..<40).map { index in
            MediaSourceItem(
                id: "b_\(index)",
                name: String(format: "B_%02d.jpg", index),
                path: "b_\(index)",
                type: .image,
                modifiedDate: Date(timeIntervalSince1970: TimeInterval(1000 + index))
            )
        }
        let trailingItems = (0..<10).map { index in
            MediaSourceItem(
                id: "z_\(index)",
                name: String(format: "Z_%02d.jpg", index),
                path: "z_\(index)",
                type: .image,
                modifiedDate: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let source = GatedStubMediaSource(
            id: "smb://sort.local",
            preferredLayout: .list,
            supportedSortKeys: [.date, .name],
            items: primaryItems + trailingItems
        )
        let viewModel = TVBrowserViewModel(
            source: source,
            folder: nil,
            preferenceStore: StubSortPreferenceStore(),
            layoutPreferenceStore: StubLayoutPreferenceStore()
        )

        await viewModel.loadInitial()
        #expect(viewModel.items.count == 40)
        #expect(viewModel.items.first?.id == "b_0")

        await source.armGate(forPage: 1, sortKey: .name)
        let stalePageTask = Task {
            await viewModel.loadNextPage()
        }
        await source.waitUntilGatedFetchStarts()
        #expect(viewModel.isPaginating)

        viewModel.applySort(key: .date)
        for _ in 0..<80 {
            if !viewModel.isLoading, viewModel.items.first?.id == "z_0" {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(!viewModel.isLoading)
        #expect(viewModel.items.first?.id == "z_0")

        await source.releaseGate()
        await stalePageTask.value

        #expect(viewModel.selectedSortKey == .date)
        #expect(viewModel.items.count == 40)
        #expect(Set(viewModel.items.map(\.id)).count == 40)
        #expect(viewModel.items.prefix(10).map(\.id) == (0..<10).map { "z_\($0)" })
        #expect(viewModel.paginationContext.nextPage == 1)
        #expect(!viewModel.isPaginating)
        #expect(viewModel.canLoadMore)
    }

    @Test("Resets isPaginating when pagination fails or throws after becoming stale")
    @MainActor
    func testNextPageErrorAndStaleErrorResetIsPaginating() async {
        let items = (0..<60).map { index in
            MediaSourceItem(
                id: "item_\(index)",
                name: String(format: "Item_%02d.jpg", index),
                path: "item_\(index)",
                type: .image
            )
        }
        let source = GatedStubMediaSource(id: "photos", items: items)
        let viewModel = TVBrowserViewModel(
            source: source,
            folder: nil,
            preferenceStore: StubSortPreferenceStore(),
            layoutPreferenceStore: StubLayoutPreferenceStore()
        )

        await viewModel.loadInitial()
        #expect(viewModel.items.count == 40)

        let pageError = NSError(domain: "TestError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Page error"])
        await source.armGate(forPage: 1, errorAfterGate: pageError)
        let failingPageTask = Task {
            await viewModel.loadNextPage()
        }
        await source.waitUntilGatedFetchStarts()
        #expect(viewModel.isPaginating)
        await source.releaseGate()
        await failingPageTask.value

        #expect(!viewModel.isPaginating)
        #expect(viewModel.items.count == 40)
        #expect(viewModel.canLoadMore)

        await source.armGate(forPage: 1, errorAfterGate: pageError)
        let staleFailingPageTask = Task {
            await viewModel.loadNextPage()
        }
        await source.waitUntilGatedFetchStarts()
        await viewModel.loadInitial(force: true)
        await source.releaseGate()
        await staleFailingPageTask.value

        #expect(!viewModel.isPaginating)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.items.count == 40)
    }

    @Test("Cancelled initial load clears isLoading without surfacing CancellationError")
    @MainActor
    func testCancelledLoadInitialResetsIsLoadingWithoutError() async {
        let items = [
            MediaSourceItem(id: "item_0", name: "Item_00.jpg", path: "item_0", type: .image)
        ]
        let source = GatedStubMediaSource(id: "photos", items: items)
        let viewModel = TVBrowserViewModel(
            source: source,
            folder: nil,
            preferenceStore: StubSortPreferenceStore(),
            layoutPreferenceStore: StubLayoutPreferenceStore()
        )

        await source.armGate(forPage: 0)
        let loadTask = Task {
            await viewModel.loadInitial()
        }
        await source.waitUntilGatedFetchStarts()
        #expect(viewModel.isLoading)

        loadTask.cancel()
        await source.releaseGate()
        await loadTask.value

        #expect(!viewModel.isLoading)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("Triggers pagination only when appearing item index reaches trailing 8-item threshold")
    @MainActor
    func testOnItemAppearIndexThresholdTriggersPagination() async throws {
        let items = (0..<55).map { index in
            MediaSourceItem(
                id: "item_\(index)",
                name: String(format: "Item_%02d.jpg", index),
                path: "item_\(index)",
                type: .image
            )
        }
        let source = GatedStubMediaSource(id: "photos", items: items)
        let viewModel = TVBrowserViewModel(
            source: source,
            folder: nil,
            preferenceStore: StubSortPreferenceStore(),
            layoutPreferenceStore: StubLayoutPreferenceStore()
        )

        await viewModel.loadInitial()
        #expect(viewModel.items.count == 40)

        viewModel.onItemAppear(at: -1)
        viewModel.onItemAppear(at: 40)
        viewModel.onItemAppear(at: 31)
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(viewModel.items.count == 40)
        #expect(await source.requestedPages == [0])

        viewModel.onItemAppear(at: 32)
        for _ in 0..<80 {
            if viewModel.items.count == 55, !viewModel.isPaginating {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(viewModel.items.count == 55)
        #expect(!viewModel.canLoadMore)
        #expect(!viewModel.isPaginating)
        #expect(await source.requestedPages == [0, 1])
    }
}
