//
//  TVBrowserViewModel.swift
//  FichierTV
//

import Foundation
import Observation
import FichierKit

/// State coordinator managing paginated media fetching, sort & layout preference persistence, and focus tracking.
@Observable
@MainActor
public final class TVBrowserViewModel {
    public let source: any MediaSource
    public let folder: MediaSourceItem?

    public private(set) var items: [MediaSourceItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isPaginating: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var canLoadMore: Bool = true

    public var selectedSortKey: MediaSortKey
    public var selectedSortOrder: MediaSortOrder = .ascending
    public private(set) var selectedLayout: MediaSourceLayout

    private let preferenceStore: any MediaSortPreferenceStoreProtocol
    private let layoutPreferenceStore: any MediaLayoutPreferenceStoreProtocol
    private var hasLoadedSavedPreference: Bool = false
    private var hasLoadedSavedLayout: Bool = false
    private var hasUserChangedSort: Bool = false
    private var hasUserChangedLayout: Bool = false
    private var currentPage: Int = 0
    private var loadGeneration: Int = 0
    private let pageSize: Int = 40

    public var firstItemID: String? {
        items.first?.id
    }

    /// Pagination metadata allowing pushed media viewers to fetch remaining pages from the source.
    public var paginationContext: TVViewerPaginationContext {
        TVViewerPaginationContext(
            sourceID: source.id,
            folder: folder,
            sortKey: selectedSortKey,
            sortOrder: selectedSortOrder,
            nextPage: currentPage + 1,
            canLoadMore: canLoadMore,
            pageSize: pageSize
        )
    }

    public init(
        source: any MediaSource,
        folder: MediaSourceItem?,
        preferenceStore: any MediaSortPreferenceStoreProtocol = DefaultMediaSortPreferenceStore.shared,
        layoutPreferenceStore: any MediaLayoutPreferenceStoreProtocol = DefaultMediaLayoutPreferenceStore.shared
    ) {
        self.source = source
        self.folder = folder
        self.preferenceStore = preferenceStore
        self.layoutPreferenceStore = layoutPreferenceStore
        self.selectedLayout = source.preferredLayout

        // Default to filename ascending (.name) on all screens displaying files or folders
        if source.supportedSortKeys.contains(.name) {
            self.selectedSortKey = .name
            self.selectedSortOrder = .ascending
        } else {
            self.selectedSortKey = source.supportedSortKeys.first ?? .name
            self.selectedSortOrder = .ascending
        }
    }

    /// Fetches the initial page of items, loading persisted sort and layout preferences first.
    public func loadInitial(force: Bool = false) async {
        guard force || !isLoading else { return }
        loadGeneration += 1
        let activeGeneration = loadGeneration
        isLoading = true
        errorMessage = nil
        currentPage = 0
        canLoadMore = true

        if !hasLoadedSavedPreference {
            hasLoadedSavedPreference = true
            if let saved = await preferenceStore.preference(for: source.id),
               activeGeneration == self.loadGeneration,
               !hasUserChangedSort,
               source.supportedSortKeys.contains(saved.key) {
                self.selectedSortKey = saved.key
                self.selectedSortOrder = saved.order
            }
        }
        guard activeGeneration == self.loadGeneration else { return }

        if !hasLoadedSavedLayout {
            hasLoadedSavedLayout = true
            if let savedLayout = await layoutPreferenceStore.layout(for: source.id),
               activeGeneration == self.loadGeneration,
               !hasUserChangedLayout {
                self.selectedLayout = savedLayout
            }
        }
        guard activeGeneration == self.loadGeneration else { return }

        do {
            let fetched = try await source.fetchItems(
                in: folder,
                sortBy: selectedSortKey,
                order: selectedSortOrder,
                page: 0,
                pageSize: pageSize
            )
            guard activeGeneration == self.loadGeneration else { return }
            self.items = fetched
            self.canLoadMore = fetched.count >= pageSize
            self.isLoading = false
        } catch {
            guard activeGeneration == self.loadGeneration else { return }
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    /// Loads the subsequent page of media items if more exist.
    public func loadNextPage() async {
        guard !isLoading, !isPaginating, canLoadMore else { return }
        isPaginating = true
        let nextPage = currentPage + 1

        do {
            let fetched = try await source.fetchItems(
                in: folder,
                sortBy: selectedSortKey,
                order: selectedSortOrder,
                page: nextPage,
                pageSize: pageSize
            )

            if fetched.isEmpty {
                self.canLoadMore = false
            } else {
                self.items.append(contentsOf: fetched)
                self.currentPage = nextPage
                self.canLoadMore = fetched.count >= pageSize
            }
            self.isPaginating = false
        } catch {
            self.isPaginating = false
        }
    }

    /// Triggers pagination when approaching the trailing items in the collection.
    public func onItemAppear(_ item: MediaSourceItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if index >= items.count - 8 {
            Task {
                await loadNextPage()
            }
        }
    }

    /// Changes sort key, persists preference per source, and refreshes data.
    public func applySort(key: MediaSortKey) {
        hasUserChangedSort = true
        hasLoadedSavedPreference = true
        guard key != selectedSortKey else { return }
        selectedSortKey = key
        let preference = MediaSortPreference(key: selectedSortKey, order: selectedSortOrder)
        Task {
            await preferenceStore.savePreference(preference, for: source.id)
            await loadInitial(force: true)
        }
    }

    /// Toggles sort direction, persists preference per source, and refreshes data.
    public func toggleSortOrder() {
        hasUserChangedSort = true
        hasLoadedSavedPreference = true
        selectedSortOrder = (selectedSortOrder == .ascending) ? .descending : .ascending
        let preference = MediaSortPreference(key: selectedSortKey, order: selectedSortOrder)
        Task {
            await preferenceStore.savePreference(preference, for: source.id)
            await loadInitial(force: true)
        }
    }

    /// Updates the visual presentation layout (`grid` or `list`) and persists preference per source.
    public func setLayout(_ layout: MediaSourceLayout) {
        hasUserChangedLayout = true
        hasLoadedSavedLayout = true
        guard layout != selectedLayout else { return }
        selectedLayout = layout
        Task {
            await layoutPreferenceStore.saveLayout(layout, for: source.id)
        }
    }

    /// Toggles the visual presentation layout between grid and list and persists preference per source.
    public func toggleLayout() {
        setLayout(selectedLayout.toggled)
    }

    /// Refreshes `selectedLayout` from the persisted per-source store (used when popping back from child folders).
    public func refreshSavedLayout() async {
        if let saved = await layoutPreferenceStore.layout(for: source.id), saved != selectedLayout {
            self.selectedLayout = saved
        }
    }

    /// Refreshes sort preferences from the persisted per-source store and reloads if changed in a child folder.
    public func refreshSavedSortPreference() async {
        if let saved = await preferenceStore.preference(for: source.id),
           source.supportedSortKeys.contains(saved.key),
           saved.key != selectedSortKey || saved.order != selectedSortOrder {
            self.selectedSortKey = saved.key
            self.selectedSortOrder = saved.order
            await loadInitial(force: true)
        }
    }
}
