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
    private var prefetchTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var memoryWarningTask: Task<Void, Never>?

    private var imageCache: [String: UIImage] = [:]
    private var imageCacheKeys: [String] = []
    private static let maxImageCacheSize = 8

    /// Adaptive animation curve for slideshow advancing and manual paging.
    public var slideAnimation: Animation {
        if isSlideshowPlaying {
            return .easeInOut(duration: 0.8)
        }
        switch transitionStyle {
        case .fade, .kenBurns:
            return .easeInOut(duration: 0.8)
        case .slide:
            return .easeInOut(duration: 0.55)
        }
    }

    /// Returns a preloaded image for a given item identifier if present in the in-memory cache.
    public func cachedImage(for id: String) -> UIImage? {
        imageCache[id]
    }

    private func cacheImage(_ image: UIImage, for id: String) {
        if imageCache[id] == nil {
            imageCacheKeys.append(id)
            if imageCacheKeys.count > Self.maxImageCacheSize {
                let evicted = imageCacheKeys.removeFirst()
                imageCache.removeValue(forKey: evicted)
            }
        }
        imageCache[id] = image
    }

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

        self.memoryWarningTask = Task { @MainActor [weak self] in
            let notifications = NotificationCenter.default.notifications(named: UIApplication.didReceiveMemoryWarningNotification)
            for await _ in notifications {
                guard let self else { break }
                self.handleMemoryWarning()
            }
        }
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

    /// Loads the full-resolution image asset for the current selection, utilizing cache when available.
    public func loadCurrentImage() {
        imageLoadTask?.cancel()

        let item = currentItem
        if let cached = imageCache[item.id] {
            self.currentImage = cached
            self.isLoadingImage = false
            prefetchNeighbors()
            return
        }

        currentImage = nil
        isLoadingImage = true

        imageLoadTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await self.fetchImage(for: item)
            guard !Task.isCancelled, !self.isTornDown else { return }
            if let loaded {
                self.cacheImage(loaded, for: item.id)
                self.currentImage = loaded
            }
            self.isLoadingImage = false
            self.prefetchNeighbors()
        }
    }

    private func fetchImage(for item: MediaSourceItem) async -> UIImage? {
        if let phID = item.phAssetIdentifier {
            return await PhotoFullImageLoader.shared.loadFullImage(for: phID)
        } else if let localURL = item.localURL {
            return UIImage(contentsOfFile: localURL.path)
        } else if let sourceID = item.sourceID,
                  let share = item.smbShare,
                  let path = item.smbPath {
            return await SMBImageLoader.shared.loadFullImage(
                sourceID: sourceID,
                share: share,
                path: path,
                resolver: resolver
            )
        }
        return nil
    }

    private func prefetchNeighbors() {
        prefetchTask?.cancel()
        guard !items.isEmpty else { return }

        var indicesToPrefetch: [Int] = []
        if currentIndex + 1 < items.count {
            indicesToPrefetch.append(currentIndex + 1)
        } else if isSlideshowPlaying && items.count > 1 {
            indicesToPrefetch.append(0)
        }
        if currentIndex > 0 {
            indicesToPrefetch.append(currentIndex - 1)
        }
        if currentIndex + 2 < items.count {
            indicesToPrefetch.append(currentIndex + 2)
        }

        let candidates = indicesToPrefetch.compactMap { idx -> MediaSourceItem? in
            guard idx >= 0 && idx < items.count else { return nil }
            let itm = items[idx]
            return imageCache[itm.id] == nil ? itm : nil
        }
        guard !candidates.isEmpty else { return }

        prefetchTask = Task { [weak self] in
            guard let self else { return }
            for candidate in candidates {
                guard !Task.isCancelled, !self.isTornDown else { break }
                if let image = await self.fetchImage(for: candidate) {
                    guard !Task.isCancelled, !self.isTornDown else { break }
                    self.cacheImage(image, for: candidate.id)
                }
            }
        }
    }

    private func scheduleNextSlide() {
        slideshowTask?.cancel()
        slideshowTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.slideshowInterval * 1_000_000_000))
            guard !Task.isCancelled, self.isSlideshowPlaying else { return }

            // Preload next image into cache before triggering transition to ensure zero-flicker cross-dissolve
            let nextIndex = (self.currentIndex + 1 < self.items.count) ? self.currentIndex + 1 : 0
            if nextIndex < self.items.count {
                let nextItem = self.items[nextIndex]
                if self.cachedImage(for: nextItem.id) == nil {
                    if let loaded = await self.fetchImage(for: nextItem) {
                        self.cacheImage(loaded, for: nextItem.id)
                    }
                }
            }
            guard !Task.isCancelled, self.isSlideshowPlaying else { return }

            withAnimation(self.slideAnimation) {
                self.showNext()
            }
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
        memoryWarningTask?.cancel()
        memoryWarningTask = nil
        imageLoadTask?.cancel()
        prefetchTask?.cancel()
        paginationTask?.cancel()
        paginationTask = nil
        imageCache.removeAll()
        imageCacheKeys.removeAll()
    }

    /// Purges cached adjacent slide frames when system emits a memory warning.
    public func handleMemoryWarning() {
        let currentID = currentItem.id
        let currentImg = imageCache[currentID]
        imageCache.removeAll()
        imageCacheKeys.removeAll()
        if let currentImg {
            imageCache[currentID] = currentImg
            imageCacheKeys.append(currentID)
        }
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
