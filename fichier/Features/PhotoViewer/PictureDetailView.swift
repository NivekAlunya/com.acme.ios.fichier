//
//  PictureDetailView.swift
//  fichier
//

import SwiftUI

public struct PictureDetailView: View {
    var manager: SMBDirectManager
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
        manager: SMBDirectManager,
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
            
            // Controls Overlay
            if showControls {
                VStack {
                    Spacer()
                    bottomUnifiedHUD
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
        .onChange(of: currentItem) { _, newItem in
            prefetchNext(after: newItem)
            Task {
                if !newItem.isVideo {
                    self.currentImage = await manager.downloadImage(for: newItem)
                } else {
                    self.currentImage = nil
                }
                self.activeMetadata = await manager.fetchMetadata(for: newItem)
            }
        }
        .onAppear {
            prefetchNext(after: currentItem)
            Task {
                if !currentItem.isVideo {
                    self.currentImage = await manager.downloadImage(for: currentItem)
                } else {
                    self.currentImage = nil
                }
                self.activeMetadata = await manager.fetchMetadata(for: currentItem)
            }
        }
    }
    
    // MARK: - Unified Bottom Floating HUD Pill
    
    private var bottomUnifiedHUD: some View {
        HStack {
            Spacer()
            
            HStack(spacing: 9) {
                // 1. Close Button
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Circle())
                }
                
                Divider()
                    .frame(height: 18)
                    .background(Color.white.opacity(0.3))
                
                // 2. Previous Photo Button
                if pictures.count > 1 {
                    Button {
                        withAnimation { goToPrevious() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                    }
                }
                
                // 3. Name & Counter
                VStack(spacing: 1) {
                    Text(currentItem.name)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: 120)
                    
                    Text(.Strings.commonItemCounterAndSize(currentIndex + 1, pictures.count, currentItem.formattedSize))
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // 4. Next Photo Button
                if pictures.count > 1 {
                    Button {
                        withAnimation { goToNext() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                    }
                }
                
                Divider()
                    .frame(height: 18)
                    .background(Color.white.opacity(0.3))
                
                // 5. Slideshow Play/Pause
                Button {
                    withAnimation { isPlayingSlideshow.toggle() }
                } label: {
                    Image(systemName: isPlayingSlideshow ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isPlayingSlideshow ? Color.orange : Color.white)
                        .padding(5)
                }
                
                // 6. Slideshow Duration & Transition Style Menu
                Menu {
                    Section(.Strings.slideshowSectionTransitionStyle) {
                        Picker(.Strings.slideshowPickerStyle, selection: $transitionStyle) {
                            ForEach(SlideshowTransitionStyle.allCases) { style in
                                Label(style.localizedTitle, systemImage: style.iconName).tag(style)
                            }
                        }
                    }
                    
                    Section(.Strings.slideshowPickerDuration) {
                        Picker(.Strings.slideshowPickerSlideshowDuration, selection: $slideshowInterval) {
                            Text(.Strings.slideshowDurationTwoSeconds).tag(2.0)
                            Text(.Strings.slideshowDurationThreeSeconds).tag(3.0)
                            Text(.Strings.slideshowDurationFiveSeconds).tag(5.0)
                            Text(.Strings.slideshowDurationTenSeconds).tag(10.0)
                            Text(.Strings.slideshowDurationFifteenSeconds).tag(15.0)
                            Text(.Strings.slideshowDurationThirtySeconds).tag(30.0)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                        Text(.Strings.slideshowDurationSecondsShort(Int(slideshowInterval)))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
                }
                
                // 7. EXIF Info Sheet
                Button {
                    Task {
                        if activeMetadata == nil {
                            self.activeMetadata = await manager.fetchMetadata(for: currentItem)
                        }
                        showingInfoSheet = true
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(5)
                }
                
                // 7. Favorite Button
                Button {
                    FavoritesManager.shared.toggleFavorite(currentItem)
                } label: {
                    Image(systemName: FavoritesManager.shared.isFavorite(currentItem) ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundStyle(FavoritesManager.shared.isFavorite(currentItem) ? Color.red : Color.white)
                        .padding(5)
                }
                
                if !currentItem.isPhotoAsset {
                    // 8. Save to Camera Roll
                    Button {
                        saveToCameraRoll()
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .padding(5)
                        }
                    }
                    .disabled(currentImage == nil || isSaving)
                }
                
                // 9. ShareLink
                if let img = currentImage {
                    ShareLink(
                        item: Image(uiImage: img),
                        preview: SharePreview(currentItem.name, image: Image(uiImage: img))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .padding(5)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
            )
            
            Spacer()
        }
        .padding(.bottom, 24)
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
