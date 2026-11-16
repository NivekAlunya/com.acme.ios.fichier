//
//  PictureDetailView.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Full-screen photo inspection and slideshow presentation coordinator.
///
/// ### Core Capabilities
/// - **Dual Display Modes**:
///   1. *Manual Browsing*: Interactive 1:1 finger swipe `TabView` with page-style gestures.
///   2. *Automated Slideshow*: Timed auto-advancing slideshow with customizable transitions (`.slide`, `.dissolve`, `.kenBurns`).
/// - **Structured Concurrency**: Spawns a structured `TaskGroup` upon photo change (`.task(id: viewModel.currentItem.id)`)
///   to fetch EXIF metadata and download full-resolution image bytes in parallel.
/// - **Lookahead Prefetching**: Automatically schedules background download of the subsequent photo (`prefetchNext`)
///   to eliminate loading pauses during manual paging or rapid slideshow playback.
/// - **Hardware Keyboard Support**: Complete iPad / Mac keyboard shortcuts (Arrow keys, Space for play/pause, `F` for favorite, `I` for info, `Esc` to close).
public struct PictureDetailView: View {
    /// Shared storage location manager providing media streaming and caching.
    var manager: StorageLocationManager
    
    /// Collection of photo items available for navigation in this session.
    let pictures: [MediaItem]
    
    /// The initial photo item focused when the viewer opened.
    let initialItem: MediaItem
    
    /// Flag indicating whether the slideshow should begin running automatically on appear.
    let autoStartSlideshow: Bool
    
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: PictureDetailViewModel
    
    /// Duration in seconds between automatic slideshow photo transitions.
    @AppStorage("slideshow_timer_interval") private var slideshowInterval: Double = 3.0
    
    /// Visual transition animation style applied in slideshow mode.
    @AppStorage("slideshow_transition_style") private var transitionStyle: SlideshowTransitionStyle = .slide

    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - manager: Shared storage location manager.
    ///   - pictures: Array of candidate media items (videos are filtered out automatically).
    ///   - initialItem: Initial focused media item.
    ///   - autoStartSlideshow: Whether to immediately begin slideshow cycling (defaults to `false`).
    public init(
        manager: StorageLocationManager,
        pictures: [MediaItem],
        initialItem: MediaItem,
        autoStartSlideshow: Bool = false
    ) {
        self.manager = manager
        let photos = pictures.filter(\.isImage)
        self.pictures = photos.isEmpty ? [initialItem] : photos
        self.initialItem = initialItem
        self.autoStartSlideshow = autoStartSlideshow
        self._viewModel = State(
            initialValue: PictureDetailViewModel(
                manager: manager,
                pictures: pictures,
                initialItem: initialItem,
                autoStartSlideshow: autoStartSlideshow
            )
        )
    }
    
    /// Zero-based index of the current photo within the active collection.
    private var currentIndex: Int {
        viewModel.currentIndex
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.isPlayingSlideshow {
                // Slideshow Mode: Simultaneous cross-dissolve with subtle scale
                ZStack {
                    ZoomablePicturePageView(
                        manager: manager,
                        item: viewModel.currentItem,
                        initialImage: viewModel.slideImageCache[viewModel.currentItem.id] ?? (viewModel.currentItem.id == initialItem.id ? viewModel.currentImage : nil),
                        onImageLoaded: { loadedImg in
                            self.viewModel.currentImage = loadedImg
                            self.viewModel.slideImageCache[viewModel.currentItem.id] = loadedImg
                        },
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.showControls.toggle()
                            }
                        }
                    )
                    .transition(activeTransition)
                    .id(viewModel.currentItem.id)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .zIndex(1)
                .contentShape(Rectangle())
                #if !os(tvOS)
                .gesture(
                    DragGesture(minimumDistance: 25)
                        .onEnded { value in
                            if value.translation.width < -40 {
                                // Swiped left -> Advance to next image
                                withAnimation(.easeInOut(duration: 0.8)) {
                                    goToNext()
                                }
                            } else if value.translation.width > 40 {
                                // Swiped right -> Return to previous image
                                withAnimation(.easeInOut(duration: 0.8)) {
                                    goToPrevious()
                                }
                            }
                        }
                )
                #endif
            } else {
                // Manual Browsing Mode: Interactive 1:1 finger swipe TabView
                TabView(selection: $viewModel.currentItem) {
                    ForEach(pictures) { pic in
                        ZoomablePicturePageView(
                            manager: manager,
                            item: pic,
                            onImageLoaded: { loadedImg in
                                if pic.id == viewModel.currentItem.id {
                                    self.viewModel.currentImage = loadedImg
                                }
                            },
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.showControls.toggle()
                                }
                            }
                        )
                        .tag(pic)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            
            // Floating HUD Overlays
            if viewModel.showControls {
                VStack {
                    PictureViewerTopBarView(
                        item: viewModel.currentItem,
                        currentIndex: currentIndex,
                        totalCount: pictures.count,
                        frameSize: viewModel.activeMetadata?.dimensions,
                        onDismiss: { dismiss() }
                    )
                    
                    Spacer()
                    
                    PictureViewerBottomBarView(
                        hasMultiplePictures: pictures.count > 1,
                        isPlayingSlideshow: $viewModel.isPlayingSlideshow,
                        slideshowInterval: $slideshowInterval,
                        transitionStyle: $transitionStyle,
                        isFavorite: FavoritesManager.shared.isFavorite(viewModel.currentItem),
                        canSaveToCameraRoll: !viewModel.currentItem.isPhotoAsset,
                        isSaving: viewModel.isSaving,
                        currentImage: viewModel.currentImage,
                        currentName: viewModel.currentItem.name,
                        onPrevious: { withAnimation(viewModel.isPlayingSlideshow ? .easeInOut(duration: 0.8) : .default) { goToPrevious() } },
                        onNext: { withAnimation(viewModel.isPlayingSlideshow ? .easeInOut(duration: 0.8) : .default) { goToNext() } },
                        onShowInfo: {
                            Task {
                                if viewModel.activeMetadata == nil {
                                    self.viewModel.activeMetadata = await manager.fetchMetadata(for: viewModel.currentItem)
                                }
                                viewModel.showingInfoSheet = true
                            }
                        },
                        onToggleFavorite: {
                            FavoritesManager.shared.toggleFavorite(viewModel.currentItem)
                        },
                        onSaveToCameraRoll: {
                            saveToCameraRoll()
                        }
                    )
                    .padding(.bottom, 20)
                }
                .transition(.opacity)
            }
            
            // Visual toast banner when saved to photos
            if let message = viewModel.saveStatusMessage {
                VStack {
                    Spacer().frame(height: 70)
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(message)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $viewModel.showingInfoSheet) {
            if let meta = viewModel.activeMetadata {
                PictureInfoSheet(metadata: meta, item: viewModel.currentItem)
            } else {
                ProgressView(.Strings.photoViewerReadingMetadata)
                    #if !os(tvOS)
                    .presentationDetents([.medium])
                    #endif
            }
        }
        // Automatic Slideshow loop (Resets timer cleanly whenever user swipes or changes picture)
        .task(id: "\(viewModel.isPlayingSlideshow)-\(viewModel.currentItem.id)-\(slideshowInterval)") {
            guard viewModel.isPlayingSlideshow, pictures.count > 1 else { return }
            do {
                try await Task.sleep(for: .seconds(slideshowInterval))
            } catch {
                return
            }
            guard viewModel.isPlayingSlideshow && !Task.isCancelled else { return }
            
            // Preload next image into cache before triggering transition to ensure zero-flicker cross-dissolve
            let nextIndex = (currentIndex + 1) % pictures.count
            let nextItem = pictures[nextIndex]
            if viewModel.slideImageCache[nextItem.id] == nil, !nextItem.isVideo {
                if let loaded = await manager.downloadImage(for: nextItem) {
                    viewModel.slideImageCache[nextItem.id] = loaded
                }
            }
            guard viewModel.isPlayingSlideshow && !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.8)) {
                goToNext()
            }
        }
        // Photo loading, EXIF extraction, and prefetching with structured cancellation on photo switch
        .task(id: viewModel.currentItem.id) {
            let targetID = viewModel.currentItem.id
            viewModel.activeMetadata = nil
            viewModel.currentImage = nil
            prefetchNext(after: viewModel.currentItem)
            
            await withTaskGroup(of: (isMeta: Bool, meta: PictureEXIFData?, image: UIImage?).self) { group in
                group.addTask {
                    let meta = await manager.fetchMetadata(for: viewModel.currentItem)
                    return (true, meta, nil)
                }
                
                if !viewModel.currentItem.isVideo {
                    group.addTask {
                        let img = await manager.downloadImage(for: viewModel.currentItem)
                        return (false, nil, img)
                    }
                }
                
                for await result in group {
                    guard !Task.isCancelled, self.viewModel.currentItem.id == targetID else {
                        group.cancelAll()
                        break
                    }
                    if result.isMeta {
                        self.viewModel.activeMetadata = result.meta
                    } else {
                        self.viewModel.currentImage = result.image
                        if let img = result.image {
                            self.viewModel.slideImageCache[targetID] = img
                        }
                    }
                }
            }
        }
        #if !os(tvOS)
        .background {
            // Hardware Keyboard Shortcuts for iPad and Mac
            Group {
                Button("") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("") { withAnimation(viewModel.isPlayingSlideshow ? .easeInOut(duration: 0.8) : .default) { goToPrevious() } }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { withAnimation(viewModel.isPlayingSlideshow ? .easeInOut(duration: 0.8) : .default) { goToNext() } }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { withAnimation(viewModel.isPlayingSlideshow ? .easeInOut(duration: 0.8) : .default) { goToPrevious() } }
                    .keyboardShortcut("[", modifiers: [])
                Button("") { withAnimation(viewModel.isPlayingSlideshow ? .easeInOut(duration: 0.8) : .default) { goToNext() } }
                    .keyboardShortcut("]", modifiers: [])
                Button("") { withAnimation { viewModel.isPlayingSlideshow.toggle() } }
                    .keyboardShortcut(.space, modifiers: [])
                Button("") { FavoritesManager.shared.toggleFavorite(viewModel.currentItem) }
                    .keyboardShortcut("f", modifiers: [])
                Button("") {
                    Task {
                        if viewModel.activeMetadata == nil {
                            self.viewModel.activeMetadata = await manager.fetchMetadata(for: viewModel.currentItem)
                        }
                        viewModel.showingInfoSheet.toggle()
                    }
                }
                .keyboardShortcut("i", modifiers: [])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        #endif
    }
    
    /// Dynamically constructs the transition animation based on user preference and trajectory direction.
    private var activeTransition: AnyTransition {
        let base: AnyTransition
        switch transitionStyle {
        case .slide:
            base = .asymmetric(
                insertion: .move(edge: viewModel.slideDirection == .forward ? .trailing : .leading)
                    .combined(with: .opacity),
                removal: .move(edge: viewModel.slideDirection == .forward ? .leading : .trailing)
                    .combined(with: .opacity)
            )
        case .dissolve:
            base = .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 1.04)),
                removal: .opacity.combined(with: .scale(scale: 0.96))
            )
        case .kenBurns:
            base = .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 1.08)),
                removal: .opacity.combined(with: .scale(scale: 0.92))
            )
        }
        return base.animation(.easeInOut(duration: 0.8))
    }
    
    // MARK: - Actions & Navigation Helpers
    
    /// Saves the currently rendered image to the system Photos library with progress feedback and toast banner.
    private func saveToCameraRoll() {
        guard let img = viewModel.currentImage else { return }
        viewModel.isSaving = true
        Task {
            do {
                try await PhotoLibrarySaver.saveImageToPhotos(img)
                withAnimation {
                    viewModel.saveStatusMessage = String(localized: .Strings.gallerySavedToPhotosSingle)
                }
            } catch {
                withAnimation {
                    viewModel.saveStatusMessage = String(localized: .Strings.commonErrorFailedToSave(error.localizedDescription))
                }
            }
            viewModel.isSaving = false
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation {
                viewModel.saveStatusMessage = nil
            }
        }
    }
    
    /// Navigates forward to the next image in the sequence, wrapping to index 0 at the end.
    private func goToNext() {
        guard !pictures.isEmpty else { return }
        viewModel.slideDirection = .forward
        let nextIndex = (currentIndex + 1) % pictures.count
        viewModel.currentItem = pictures[nextIndex]
    }
    
    /// Navigates backward to the previous image in the sequence, wrapping to the last item at the start.
    private func goToPrevious() {
        guard !pictures.isEmpty else { return }
        viewModel.slideDirection = .backward
        let prevIndex = (currentIndex - 1 + pictures.count) % pictures.count
        viewModel.currentItem = pictures[prevIndex]
    }
    
    /// Dispatches an asynchronous prefetch task for the next upcoming photo into memory/disk cache.
    ///
    /// - Parameter item: Current media item.
    private func prefetchNext(after item: MediaItem) {
        guard let idx = pictures.firstIndex(where: { $0.id == item.id }), pictures.count > 1 else { return }
        let nextIdx = (idx + 1) % pictures.count
        let nextItem = pictures[nextIdx]
        guard !nextItem.isVideo else { return }
        Task {
            if let img = await manager.downloadImage(for: nextItem) {
                viewModel.slideImageCache[nextItem.id] = img
            }
        }
    }
}
