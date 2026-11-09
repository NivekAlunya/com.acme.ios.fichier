//
//  TVImageViewerViewModel.swift
//  FichierTV
//

import SwiftUI
import Observation
import FichierKit

/// State coordinator driving image navigation, high-resolution loading, and slideshow cycling.
@Observable
@MainActor
public final class TVImageViewerViewModel {
    public private(set) var items: [MediaSourceItem]
    public private(set) var currentIndex: Int
    public private(set) var currentImage: UIImage?
    public private(set) var isLoadingImage: Bool = false
    public private(set) var isLoadingMoreImages: Bool = false
    public private(set) var isSlideshowPlaying: Bool = false
    public private(set) var transitionDirection: SlideDirection = .forward
    public var showOverlay: Bool = false

    public private(set) var slideshowInterval: TimeInterval = 4.0
    public private(set) var transitionStyle: SlideshowTransitionStyle = .slide
    public var isShowingSettingsSheet: Bool = false

    private let settingsStore: any SlideshowSettingsStoreProtocol
    private let resolver: any MediaSourceResolverProtocol
    private let paginationContext: TVViewerPaginationContext?
    private var paginationSource: (any MediaSource)?
    private var nextPageToFetch: Int
    private var hasMoreSourcePages: Bool
    private var seenItemIDs: Set<String>
    private var pendingAdvanceOnPagination: Bool = false
    private var pendingAdvanceWrapOnEnd: Bool = false
    private var isTornDown: Bool = false

    private var slideshowTask: Task<Void, Never>?
    private var imageLoadTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?

    public var currentItem: MediaSourceItem {
        guard !items.isEmpty, currentIndex >= 0, currentIndex < items.count else {
            return MediaSourceItem(id: "empty", name: "", path: "", type: .image)
        }
        return items[currentIndex]
    }

    public var canNavigatePrevious: Bool {
        currentIndex > 0
    }

    public var canNavigateNext: Bool {
        currentIndex < items.count - 1 || hasMoreSourcePages
    }

    public init(
        initialItem: MediaSourceItem,
        items: [MediaSourceItem],
        paginationContext: TVViewerPaginationContext? = nil,
        source: (any MediaSource)? = nil,
        settingsStore: any SlideshowSettingsStoreProtocol = DefaultSlideshowSettingsStore.shared,
        resolver: any MediaSourceResolverProtocol = DefaultMediaSourceResolver.shared
    ) {
        var seen: Set<String> = []
        var filteredImages = Self.filterAndDeduplicateImages(items, existingIDs: &seen)
        let resolvedItems: [MediaSourceItem]
        let resolvedSeenIDs: Set<String>
        if filteredImages.isEmpty {
            resolvedItems = [initialItem]
            resolvedSeenIDs = [initialItem.id]
        } else {
            if Self.isValidImageItem(initialItem) && seen.insert(initialItem.id).inserted {
                filteredImages.insert(initialItem, at: 0)
            }
            resolvedItems = filteredImages
            resolvedSeenIDs = seen
        }
        let initialIndex = resolvedItems.firstIndex(where: { $0.id == initialItem.id }) ?? 0
        self.items = resolvedItems
        self.seenItemIDs = resolvedSeenIDs
        self.currentIndex = initialIndex
        self.paginationContext = paginationContext
        self.paginationSource = source
        self.nextPageToFetch = paginationContext?.nextPage ?? 0
        self.hasMoreSourcePages = paginationContext?.canLoadMore ?? false
        self.settingsStore = settingsStore
        self.resolver = resolver
    }

    /// Loads saved interval and transition style preferences.
    public func loadSettings() async {
        self.slideshowInterval = await settingsStore.loadInterval()
        self.transitionStyle = await settingsStore.loadTransitionStyle()
    }

    /// Updates and persists slideshow slide duration.
    public func updateInterval(_ interval: TimeInterval) {
        self.slideshowInterval = interval
        Task {
            await settingsStore.saveInterval(interval)
        }
        if isSlideshowPlaying {
            scheduleNextSlide()
        }
    }

    /// Updates and persists slideshow transition style.
    public func updateTransitionStyle(_ style: SlideshowTransitionStyle) {
        self.transitionStyle = style
        Task {
            await settingsStore.saveTransitionStyle(style)
        }
    }

    /// Advances to the next image in the collection, loading subsequent source pages when needed.
    public func showNext() {
        if currentIndex < items.count - 1 {
            transitionDirection = .forward
            currentIndex += 1
            loadCurrentImage()
            scheduleLookaheadIfNeeded()
        } else if hasMoreSourcePages {
            loadMoreAndAdvance(wrapIfNoMore: isSlideshowPlaying)
        } else if isSlideshowPlaying {
            // Loop around when slideshow reaches the end
            transitionDirection = .forward
            currentIndex = 0
            loadCurrentImage()
        }
    }

    /// Prefetches remaining image pages ahead of the current index so Next skips video runs seamlessly.
    public func prefetchRemainingImagesIfNeeded() async {
        let bufferedAhead = (items.count - 1) - currentIndex
        guard hasMoreSourcePages, bufferedAhead <= 12 else { return }
        if let activeTask = paginationTask {
            await activeTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performFetchLookaheadImages(targetBufferCount: 12)
        }
        paginationTask = task
        await task.value
    }

    /// Moves back to the previous image.
    public func showPrevious() {
        pendingAdvanceOnPagination = false
        pendingAdvanceWrapOnEnd = false
        if currentIndex > 0 {
            transitionDirection = .backward
            currentIndex -= 1
            loadCurrentImage()
        }
    }

    /// Toggles the automated slideshow timer.
    public func toggleSlideshow() {
        if isSlideshowPlaying {
            stopSlideshow()
        } else {
            startSlideshow()
        }
    }

    /// Starts automated slideshow cycling.
    public func startSlideshow() {
        isSlideshowPlaying = true
        showOverlay = false
        scheduleNextSlide()
    }

    /// Stops active slideshow playback.
    public func stopSlideshow() {
        isSlideshowPlaying = false
        slideshowTask?.cancel()
        slideshowTask = nil
    }

    /// Toggles on-screen control overlay.
    public func toggleOverlay() {
        showOverlay.toggle()
    }

    /// Explicitly updates overlay visibility.
    public func setOverlayVisible(_ visible: Bool) {
        showOverlay = visible
    }

    /// Loads the full-resolution image asset for the current selection.
    public func loadCurrentImage() {
        imageLoadTask?.cancel()
        currentImage = nil
        isLoadingImage = true

        let item = currentItem
        imageLoadTask = Task {
            if let phID = item.phAssetIdentifier {
                let image = await PhotoFullImageLoader.shared.loadFullImage(for: phID)
                if !Task.isCancelled {
                    self.currentImage = image
                    self.isLoadingImage = false
                }
            } else if let localURL = item.localURL {
                let image = UIImage(contentsOfFile: localURL.path)
                if !Task.isCancelled {
                    self.currentImage = image
                    self.isLoadingImage = false
                }
            } else if let sourceID = item.sourceID,
                      let share = item.smbShare,
                      let path = item.smbPath {
                let image = await SMBImageLoader.shared.loadFullImage(
                    sourceID: sourceID,
                    share: share,
                    path: path,
                    resolver: resolver
                )
                if !Task.isCancelled {
                    self.currentImage = image
                    self.isLoadingImage = false
                }
            } else {
                self.isLoadingImage = false
            }
        }
    }

    private func scheduleNextSlide() {
        slideshowTask?.cancel()
        slideshowTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.slideshowInterval * 1_000_000_000))
            guard !Task.isCancelled, self.isSlideshowPlaying else { return }
            self.showNext()
            if self.isSlideshowPlaying {
                self.scheduleNextSlide()
            }
        }
    }

    /// Halts all background tasks upon view tear down.
    public func tearDown() {
        isTornDown = true
        pendingAdvanceOnPagination = false
        stopSlideshow()
        imageLoadTask?.cancel()
        paginationTask?.cancel()
        paginationTask = nil
    }

    // MARK: - Multi-Page Source Lookahead & Image Filtering

    private func scheduleLookaheadIfNeeded() {
        let bufferedAhead = (items.count - 1) - currentIndex
        guard hasMoreSourcePages, bufferedAhead <= 10, paginationTask == nil else { return }
        paginationTask = Task { [weak self] in
            guard let self else { return }
            await self.performFetchLookaheadImages(targetBufferCount: 12)
        }
    }

    private func loadMoreAndAdvance(wrapIfNoMore: Bool) {
        pendingAdvanceWrapOnEnd = pendingAdvanceWrapOnEnd || wrapIfNoMore
        pendingAdvanceOnPagination = true
        guard paginationTask == nil else { return }
        paginationTask = Task { [weak self] in
            guard let self else { return }
            await self.performFetchLookaheadImages(targetBufferCount: 12)
        }
    }

    private func performFetchLookaheadImages(targetBufferCount: Int) async {
        defer { paginationTask = nil }
        guard !isTornDown, hasMoreSourcePages, let context = paginationContext else {
            pendingAdvanceOnPagination = false
            return
        }

        isLoadingMoreImages = true
        defer { isLoadingMoreImages = false }

        if paginationSource == nil {
            paginationSource = await resolver.resolve(sourceID: context.sourceID)
        }
        guard !Task.isCancelled, !isTornDown, let source = paginationSource else {
            hasMoreSourcePages = false
            pendingAdvanceOnPagination = false
            return
        }

        while !Task.isCancelled && !isTornDown && hasMoreSourcePages {
            let bufferedAhead = (items.count - 1) - currentIndex
            if !pendingAdvanceOnPagination && bufferedAhead >= targetBufferCount {
                break
            }

            let page = nextPageToFetch
            do {
                let fetched = try await source.fetchItems(
                    in: context.folder,
                    sortBy: context.sortKey,
                    order: context.sortOrder,
                    page: page,
                    pageSize: context.pageSize
                )
                guard !Task.isCancelled, !isTornDown else { break }

                nextPageToFetch = page + 1
                if fetched.count < context.pageSize {
                    hasMoreSourcePages = false
                }

                let newImages = Self.filterAndDeduplicateImages(fetched, existingIDs: &seenItemIDs)
                if !newImages.isEmpty {
                    items.append(contentsOf: newImages)
                    if pendingAdvanceOnPagination && currentIndex < items.count - 1 {
                        pendingAdvanceOnPagination = false
                        pendingAdvanceWrapOnEnd = false
                        transitionDirection = .forward
                        currentIndex += 1
                        loadCurrentImage()
                    }
                }
            } catch is CancellationError {
                break
            } catch {
                if !Task.isCancelled && !isTornDown {
                    hasMoreSourcePages = false
                }
                break
            }
        }

        if pendingAdvanceOnPagination {
            let shouldWrap = pendingAdvanceWrapOnEnd
            pendingAdvanceOnPagination = false
            pendingAdvanceWrapOnEnd = false
            if currentIndex < items.count - 1 {
                transitionDirection = .forward
                currentIndex += 1
                loadCurrentImage()
            } else if shouldWrap && items.count > 1 {
                transitionDirection = .forward
                currentIndex = 0
                loadCurrentImage()
            }
        }
    }

    private static func filterAndDeduplicateImages(
        _ candidates: [MediaSourceItem],
        existingIDs: inout Set<String>
    ) -> [MediaSourceItem] {
        var result: [MediaSourceItem] = []
        result.reserveCapacity(candidates.count)
        for candidate in candidates {
            guard isValidImageItem(candidate) else { continue }
            if existingIDs.insert(candidate.id).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    private static func isValidImageItem(_ item: MediaSourceItem) -> Bool {
        guard item.type == .image else { return false }
        let ext = (item.name as NSString).pathExtension.lowercased()
        return !SupportedMediaTypes.isVideo(extension: ext)
    }
}
