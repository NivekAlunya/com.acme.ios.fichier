//
//  PictureDetailView.swift
//  fichier
//

import SwiftUI

public struct PictureDetailView: View {
    var manager: StorageLocationManager
    let pictures: [MediaItem]
    let initialItem: MediaItem
    let autoStartSlideshow: Bool
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentItem: MediaItem
    @State private var isPlayingSlideshow: Bool
    @State private var slideDirection: SlideDirection = .forward
    @AppStorage("slideshow_timer_interval") private var slideshowInterval: Double = 3.0
    @AppStorage("slideshow_transition_style") private var transitionStyle: SlideshowTransitionStyle = .slide
    @State private var showControls: Bool = true
    
    // Tier 1 features
    @State private var currentImage: UIImage?
    @State private var activeMetadata: PictureEXIFData?
    @State private var showingInfoSheet = false
    @State private var saveStatusMessage: String?
    @State private var isSaving = false
    
    public init(
        manager: StorageLocationManager,
        pictures: [MediaItem],
        initialItem: MediaItem,
        autoStartSlideshow: Bool = false
    ) {
        self.manager = manager
        let photos = pictures.filter { !$0.isVideo }
        self.pictures = photos.isEmpty ? [initialItem] : photos
        self.initialItem = initialItem
        self.autoStartSlideshow = autoStartSlideshow
        self._currentItem = State(initialValue: initialItem)
        self._isPlayingSlideshow = State(initialValue: autoStartSlideshow)
    }
    
    private var currentIndex: Int {
        pictures.firstIndex(where: { $0.id == currentItem.id }) ?? 0
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isPlayingSlideshow {
                // Slideshow Mode: Smooth Sliding Transition between Photos
                ZStack {
                    ZoomablePicturePageView(
                        manager: manager,
                        item: currentItem,
                        onImageLoaded: { loadedImg in
                            self.currentImage = loadedImg
                        },
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                        }
                    )
                    .id(currentItem.id)
                    .transition(activeTransition)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 25)
                        .onEnded { value in
                            if value.translation.width < -40 {
                                // Swiped left -> Advance to next image
                                withAnimation(.easeInOut(duration: 0.55)) {
                                    goToNext()
                                }
                            } else if value.translation.width > 40 {
                                // Swiped right -> Return to previous image
                                withAnimation(.easeInOut(duration: 0.55)) {
                                    goToPrevious()
                                }
                            }
                        }
                )
            } else {
                // Manual Browsing Mode: Interactive 1:1 finger swipe TabView
                TabView(selection: $currentItem) {
                    ForEach(pictures) { pic in
                        ZoomablePicturePageView(
                            manager: manager,
                            item: pic,
                            onImageLoaded: { loadedImg in
                                if pic.id == currentItem.id {
                                    self.currentImage = loadedImg
                                }
                            },
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showControls.toggle()
                                }
                            }
                        )
                        .tag(pic)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            
            // Floating HUD Overlays
            if showControls {
                VStack {
                    PictureViewerTopBarView(
                        item: currentItem,
                        currentIndex: currentIndex,
                        totalCount: pictures.count,
                        onDismiss: { dismiss() }
                    )
                    
                    Spacer()
                    
                    PictureViewerBottomBarView(
                        hasMultiplePictures: pictures.count > 1,
                        isPlayingSlideshow: $isPlayingSlideshow,
                        slideshowInterval: $slideshowInterval,
                        transitionStyle: $transitionStyle,
                        isFavorite: FavoritesManager.shared.isFavorite(currentItem),
                        canSaveToCameraRoll: !currentItem.isPhotoAsset,
                        isSaving: isSaving,
                        currentImage: currentImage,
                        currentName: currentItem.name,
                        onPrevious: { withAnimation { goToPrevious() } },
                        onNext: { withAnimation { goToNext() } },
                        onShowInfo: {
                            Task {
                                if activeMetadata == nil {
                                    self.activeMetadata = await manager.fetchMetadata(for: currentItem)
                                }
                                showingInfoSheet = true
                            }
                        },
                        onToggleFavorite: {
                            FavoritesManager.shared.toggleFavorite(currentItem)
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
            if let message = saveStatusMessage {
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
        .sheet(isPresented: $showingInfoSheet) {
            if let meta = activeMetadata {
                PictureInfoSheet(metadata: meta, item: currentItem)
            } else {
                ProgressView(.Strings.photoViewerReadingMetadata)
                    .presentationDetents([.medium])
            }
        }
        // Automatic Slideshow loop (Resets timer cleanly whenever user swipes or changes picture)
        .task(id: "\(isPlayingSlideshow)-\(currentItem.id)-\(slideshowInterval)") {
            guard isPlayingSlideshow, pictures.count > 1 else { return }
            do {
                try await Task.sleep(for: .seconds(slideshowInterval))
            } catch {
                return
            }
            guard isPlayingSlideshow && !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                goToNext()
            }
        }
        // Photo loading, EXIF extraction, and prefetching with structured cancellation on photo switch
        .task(id: currentItem.id) {
            activeMetadata = nil
            currentImage = nil
            prefetchNext(after: currentItem)
            
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    let meta = await manager.fetchMetadata(for: currentItem)
                    if !Task.isCancelled {
                        self.activeMetadata = meta
                    }
                }
                
                if !currentItem.isVideo {
                    group.addTask { @MainActor in
                        let img = await manager.downloadImage(for: currentItem)
                        if !Task.isCancelled {
                            self.currentImage = img
                        }
                    }
                }
            }
        }
        .background {
            // Hardware Keyboard Shortcuts for iPad and Mac
            Group {
                Button("") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("") { withAnimation { goToPrevious() } }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { withAnimation { goToNext() } }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { withAnimation { goToPrevious() } }
                    .keyboardShortcut("[", modifiers: [])
                Button("") { withAnimation { goToNext() } }
                    .keyboardShortcut("]", modifiers: [])
                Button("") { withAnimation { isPlayingSlideshow.toggle() } }
                    .keyboardShortcut(.space, modifiers: [])
                Button("") { FavoritesManager.shared.toggleFavorite(currentItem) }
                    .keyboardShortcut("f", modifiers: [])
                Button("") {
                    Task {
                        if activeMetadata == nil {
                            self.activeMetadata = await manager.fetchMetadata(for: currentItem)
                        }
                        showingInfoSheet.toggle()
                    }
                }
                .keyboardShortcut("i", modifiers: [])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }
    
    private var activeTransition: AnyTransition {
        switch transitionStyle {
        case .slide:
            return .asymmetric(
                insertion: .move(edge: slideDirection == .forward ? .trailing : .leading)
                    .combined(with: .opacity),
                removal: .move(edge: slideDirection == .forward ? .leading : .trailing)
                    .combined(with: .opacity)
            )
        case .dissolve:
            return .opacity
        case .kenBurns:
            return .opacity.combined(with: .scale(scale: 0.94))
        }
    }
    
    // MARK: - Actions & Navigation Helpers
    
    private func saveToCameraRoll() {
        guard let img = currentImage else { return }
        isSaving = true
        Task {
            do {
                try await PhotoLibrarySaver.saveImageToPhotos(img)
                withAnimation {
                    saveStatusMessage = String(localized: .Strings.photoViewerSavedToPhotos)
                }
            } catch {
                withAnimation {
                    saveStatusMessage = String(localized: .Strings.commonErrorFailedToSave(error.localizedDescription))
                }
            }
            isSaving = false
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation {
                saveStatusMessage = nil
            }
        }
    }
    
    private func goToNext() {
        guard !pictures.isEmpty else { return }
        slideDirection = .forward
        let nextIndex = (currentIndex + 1) % pictures.count
        currentItem = pictures[nextIndex]
    }
    
    private func goToPrevious() {
        guard !pictures.isEmpty else { return }
        slideDirection = .backward
        let prevIndex = (currentIndex - 1 + pictures.count) % pictures.count
        currentItem = pictures[prevIndex]
    }
    
    private func prefetchNext(after item: MediaItem) {
        guard let idx = pictures.firstIndex(where: { $0.id == item.id }), pictures.count > 1 else { return }
        let nextIdx = (idx + 1) % pictures.count
        let nextItem = pictures[nextIdx]
        guard !nextItem.isVideo else { return }
        Task {
            _ = await manager.downloadImage(for: nextItem)
        }
    }
}
