//
//  MediaGridView.swift
//  fichier
//

import SwiftUI
import OSLog

struct MediaGridView: View {
    var manager: SMBDirectManager
    var onSelectFolder: ((MediaItem) -> Void)? = nil
    var onStartSlideshow: (([MediaItem]) -> Void)? = nil
    let onSelectPicture: (MediaItem, [MediaItem]) -> Void
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("gallery_view_mode") private var viewMode: ViewMode = .grid
    @AppStorage("gallery_sort_option") private var sortOption: SortOption = .nameAsc
    @AppStorage("gallery_grid_size") private var gridSize: GridSize = .medium
    @AppStorage("slideshow_timer_interval") private var slideshowInterval: Double = 3.0
    @AppStorage("slideshow_transition_style") private var transitionStyle: SlideshowTransitionStyle = .slide
    @State private var searchText = ""
    @State private var lastPinchScale: CGFloat = 1.0
    @State private var showFavoritesOnly = false
    @State private var mediaFilter: MediaFilter = .all
    @State private var isSelectionMode = false
    @State private var selectedItems: Set<MediaItem> = []
    @State private var isBatchProcessing = false
    @State private var batchProgressMessage: String?
    @State private var batchStatusToast: String?
    @State private var batchTask: Task<Void, Never>?
    @State private var shareSheetItems: [Any]?
    @State private var showingSettings = false
    
    private var currentDirectoryID: String {
        manager.selectedFolder?.id ?? "root"
    }
    
    // MARK: - Filtered and Sorted Data
    
    private func filterAndSortData() -> (folders: [MediaItem], pictures: [MediaItem]) {
        let listFolders = searchText.isEmpty ? manager.currentFolders : manager.currentFolders.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        let sortedFolders = sortItems(listFolders)
        
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
            listPictures = listPictures.filter { !$0.isVideo }
        case .videos:
            listPictures = listPictures.filter { $0.isVideo }
        }
        let sortedPictures = sortItems(listPictures)
        return (sortedFolders, sortedPictures)
    }
    
    private func mediaSectionHeader(for count: Int) -> LocalizedStringResource {
        switch mediaFilter {
        case .all: return .Strings.gallerySectionMediaCount(count)
        case .photos: return .Strings.gallerySectionPhotosCount(count)
        case .videos: return .Strings.gallerySectionVideosCount(count)
        }
    }
    
    private func sortItems(_ items: [MediaItem]) -> [MediaItem] {
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
    
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: gridSize.minDimension, maximum: gridSize.minDimension * 1.45), spacing: 10)]
    }
    
    var body: some View {
        let (displayFolders, displayPictures) = filterAndSortData()
        
        ZStack(alignment: .bottom) {
            Group {
                if manager.isLoading && manager.pictures.isEmpty && manager.currentFolders.isEmpty {
                    ProgressView(.Strings.galleryLoadingFolderContents)
                } else if let error = manager.errorMessage, manager.pictures.isEmpty {
                    ContentUnavailableView {
                        Label(.Strings.galleryErrorUnableToLoadFolder, systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        if let folder = manager.selectedFolder {
                            Button(.Strings.commonRetry) {
                                Task { await manager.selectAndLoadFolder(folder) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else if !searchText.isEmpty && displayPictures.isEmpty && displayFolders.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if manager.pictures.isEmpty && manager.currentFolders.isEmpty {
                    ContentUnavailableView(
                        String(localized: .Strings.galleryEmptyFolderTitle),
                        systemImage: "photo.on.rectangle.angled",
                        description: Text(.Strings.galleryEmptyFolderDescription(manager.selectedFolder?.name ?? String(localized: .Strings.galleryEmptyFolderDefaultName)))
                    )
                } else {
                    switch viewMode {
                    case .grid:
                        gridContent(folders: displayFolders, pictures: displayPictures)
                    case .list:
                        listContent(folders: displayFolders, pictures: displayPictures)
                    }
                }
            }
            
            // Bottom Action Bar when in Selection Mode
            if isSelectionMode {
                MediaSelectionBottomBar(
                    selectedCount: selectedItems.count,
                    isAllFavorites: !selectedItems.isEmpty && selectedItems.allSatisfy { FavoritesManager.shared.isFavorite($0) },
                    isProcessing: isBatchProcessing,
                    progressMessage: batchProgressMessage,
                    showSaveToPhotos: manager.currentLocation?.kind != .photos,
                    onCancel: { cancelBatchTask() },
                    onToggleFavorite: { batchToggleFavorites() },
                    onSaveToPhotos: { batchSaveToPhotos() },
                    onShare: { batchShare() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Status Toast Banner (e.g. Saved to Photos)
            if let toast = batchStatusToast {
                VStack {
                    Spacer().frame(height: 70)
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(toast)
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
        .searchable(text: $searchText, prompt: .Strings.gallerySearchPrompt)
        .sheet(isPresented: Binding(
            get: { shareSheetItems != nil },
            set: { if !$0 { shareSheetItems = nil } }
        )) {
            if let shareSheetItems {
                MediaActivityShareSheet(activityItems: shareSheetItems)
            }
        }
        .sheet(isPresented: $showingSettings) {
            AppSettingsView()
        }
        .toolbar {
            if isSelectionMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selectedItems.count == displayPictures.count && !displayPictures.isEmpty ? .Strings.galleryButtonDeselectAll : .Strings.galleryButtonSelectAll) {
                        toggleAllSelection(for: displayPictures)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text(selectedItems.isEmpty ? .Strings.gallerySelectionPrompt : .Strings.gallerySelectionCount(selectedItems.count))
                        .font(.headline)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(.Strings.commonDone) {
                        withAnimation {
                            isSelectionMode = false
                            selectedItems.removeAll()
                        }
                    }
                    .font(.body.bold())
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        if !displayPictures.isEmpty {
                            Button(.Strings.galleryButtonSelect) {
                                withAnimation {
                                    isSelectionMode = true
                                }
                            }
                        }
                        
                        // Slideshow trigger & duration menu
                        if !displayPictures.isEmpty {
                            Menu {
                                Button {
                                    onStartSlideshow?(displayPictures)
                                } label: {
                                    Label(.Strings.gallerySlideshowStart, systemImage: "play.fill")
                                }
                                
                                Section(.Strings.slideshowSectionTransitionStyle) {
                                    Picker(.Strings.slideshowPickerTransition, selection: $transitionStyle) {
                                        ForEach(SlideshowTransitionStyle.allCases) { style in
                                            Label(style.localizedTitle, systemImage: style.iconName).tag(style)
                                        }
                                    }
                                }
                                
                                Section(.Strings.slideshowSectionSlideDuration) {
                                    Picker(.Strings.slideshowPickerDuration, selection: $slideshowInterval) {
                                        Text(.Strings.slideshowDurationTwoSeconds).tag(2.0)
                                        Text(.Strings.slideshowDurationThreeSeconds).tag(3.0)
                                        Text(.Strings.slideshowDurationFiveSeconds).tag(5.0)
                                        Text(.Strings.slideshowDurationTenSeconds).tag(10.0)
                                        Text(.Strings.slideshowDurationFifteenSeconds).tag(15.0)
                                        Text(.Strings.slideshowDurationThirtySeconds).tag(30.0)
                                    }
                                }
                            } label: {
                                Label(.Strings.galleryMenuSlideshow, systemImage: "play.circle.fill")
                            } primaryAction: {
                                onStartSlideshow?(displayPictures)
                            }
                        }
                        
                        // Unified View, Sort & Grid Size Menu
                        Menu {
                            Section(.Strings.galleryMenuLayout) {
                                Picker(.Strings.galleryMenuViewMode, selection: $viewMode) {
                                    Label(.Strings.galleryViewModeGrid, systemImage: "square.grid.2x2").tag(ViewMode.grid)
                                    Label(.Strings.galleryViewModeList, systemImage: "list.bullet").tag(ViewMode.list)
                                }
                            }
                            
                            if viewMode == .grid {
                                Section(.Strings.galleryMenuGridDensity) {
                                    Picker(.Strings.galleryPickerGridSize, selection: $gridSize.animation(.spring(response: 0.38, dampingFraction: 0.8))) {
                                        ForEach(GridSize.allCases) { size in
                                            Label(size.localizedTitle, systemImage: size.iconName).tag(size)
                                        }
                                    }
                                }
                            }
                            
                            Section(.Strings.galleryMenuFilter) {
                                Picker(.Strings.galleryPickerMediaType, selection: $mediaFilter) {
                                    ForEach(MediaFilter.allCases) { filter in
                                        Label(filter.localizedTitle, systemImage: filter.iconName).tag(filter)
                                    }
                                }
                                
                                Toggle(isOn: $showFavoritesOnly) {
                                    Label(.Strings.galleryFilterFavoritesOnly, systemImage: "heart.fill")
                                }
                            }
                            
                            Section(.Strings.galleryMenuSortBy) {
                                Picker(.Strings.galleryMenuSortBy, selection: $sortOption) {
                                    ForEach(SortOption.allCases) { option in
                                        Label(option.localizedTitle, systemImage: option.iconName).tag(option)
                                    }
                                }
                            }
                            
                            Section(.Strings.galleryMenuSlideshow) {
                                Picker(.Strings.slideshowPickerTransition, selection: $transitionStyle) {
                                    ForEach(SlideshowTransitionStyle.allCases) { style in
                                        Label(style.localizedTitle, systemImage: style.iconName).tag(style)
                                    }
                                }
                                
                                Picker(.Strings.slideshowSectionSlideDuration, selection: $slideshowInterval) {
                                    Text(.Strings.slideshowDurationTwoSeconds).tag(2.0)
                                    Text(.Strings.slideshowDurationThreeSeconds).tag(3.0)
                                    Text(.Strings.slideshowDurationFiveSeconds).tag(5.0)
                                    Text(.Strings.slideshowDurationTenSeconds).tag(10.0)
                                    Text(.Strings.slideshowDurationFifteenSeconds).tag(15.0)
                                    Text(.Strings.slideshowDurationThirtySeconds).tag(30.0)
                                }
                            }
                            
                            Section(String(localized: .Strings.gallerySectionDiskCache(manager.mediaCacheSize))) {
                                Button(role: .destructive) {
                                    manager.clearMediaCache()
                                } label: {
                                    Label(.Strings.galleryButtonClearCache, systemImage: "trash")
                                }
                            }
                            
                            if horizontalSizeClass == .compact {
                                Section {
                                    Button {
                                        showingSettings = true
                                    } label: {
                                        Label(.Strings.settingsTitle, systemImage: "gearshape")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: (mediaFilter != .all || showFavoritesOnly) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                        
                        Button {
                            if let folder = manager.selectedFolder {
                                Task { await manager.selectAndLoadFolder(folder) }
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        
                        if horizontalSizeClass == .compact {
                            Button {
                                showingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel(.Strings.settingsTitle)
                        }
                    }
                }
            }
        }
        .task {
            await manager.refreshMediaCacheSize()
        }
        .onDisappear {
            batchTask?.cancel()
            batchTask = nil
        }
        .background {
            // Hardware Keyboard Shortcuts for iPad and Mac
            Group {
                // Space: Start slideshow of pictures in current folder
                Button("") {
                    if !displayPictures.isEmpty {
                        onStartSlideshow?(displayPictures)
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                
                // Escape: Cancel batch selection mode
                Button("") {
                    if isSelectionMode {
                        withAnimation {
                            isSelectionMode = false
                            selectedItems.removeAll()
                            cancelBatchTask()
                        }
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                // Cmd+A: Select All / Deselect All (when in selection mode)
                Button("") {
                    if isSelectionMode {
                        toggleAllSelection(for: displayPictures)
                    } else if !displayPictures.isEmpty {
                        withAnimation {
                            isSelectionMode = true
                            selectedItems = Set(displayPictures)
                        }
                    }
                }
                .keyboardShortcut("a", modifiers: [.command])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }
    
    // MARK: - Grid Mode
    
    @ViewBuilder
    private func gridContent(folders: [MediaItem], pictures: [MediaItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id("topOfGrid")
                
                VStack(alignment: .leading, spacing: 16) {
                    if !folders.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(.Strings.gallerySectionSubfoldersCount(folders.count))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 8)], spacing: 8) {
                                ForEach(folders) { subfolder in
                                    Button {
                                        onSelectFolder?(subfolder)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "folder.fill")
                                                .foregroundColor(.blue)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(subfolder.name)
                                                    .font(.subheadline)
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)
                                                if let d = subfolder.formattedDate {
                                                    Text(d)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(10)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    
                    if !pictures.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(mediaSectionHeader(for: pictures.count))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(sortOption.localizedTitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            
                            LazyVGrid(columns: gridColumns, spacing: 10) {
                                ForEach(pictures) { pic in
                                    MediaThumbnailCell(
                                        manager: manager,
                                        item: pic,
                                        maxDimension: gridSize.thumbnailPixels,
                                        isSelected: selectedItems.contains(pic),
                                        isSelectionMode: isSelectionMode
                                    )
                                    .onTapGesture {
                                        if isSelectionMode {
                                            toggleSelection(for: pic)
                                        } else {
                                            onSelectPicture(pic, pictures)
                                        }
                                    }
                                    .onLongPressGesture {
                                        if !isSelectionMode {
                                            withAnimation {
                                                isSelectionMode = true
                                                selectedItems.insert(pic)
                                            }
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: gridSize)
                        }
                    } else if !folders.isEmpty {
                        ContentUnavailableView(
                            String(localized: .Strings.galleryNoPicturesTitle),
                            systemImage: "photo",
                            description: Text(.Strings.galleryNoPicturesDescription)
                        )
                        .padding(.top, 24)
                    }
                }
                .padding(.vertical, 12)
            }
            .id(currentDirectoryID)
            .onChange(of: currentDirectoryID) { _, _ in
                proxy.scrollTo("topOfGrid", anchor: .top)
            }
            .onChange(of: manager.isLoading) { wasLoading, isLoading in
                if wasLoading && !isLoading {
                    proxy.scrollTo("topOfGrid", anchor: .top)
                }
            }
            .refreshable {
                if let folder = manager.selectedFolder {
                    await manager.selectAndLoadFolder(folder)
                } else {
                    await manager.refreshSharesAndFolders()
                }
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let scale = value.magnification
                        let ratio = scale / lastPinchScale
                        
                        // Pinch out (fingers spreading) -> enlarge thumbnails
                        if ratio > 1.25 {
                            zoomInGrid()
                            lastPinchScale = scale
                        }
                        // Pinch in (fingers coming together) -> shrink thumbnails
                        else if ratio < 0.78 {
                            zoomOutGrid()
                            lastPinchScale = scale
                        }
                    }
                    .onEnded { _ in
                        lastPinchScale = 1.0
                    }
            )
        }
    }
    
    // MARK: - Pinch Zoom Helpers
    
    private func zoomInGrid() {
        switch gridSize {
        case .compact:
            $gridSize.animation(.spring(response: 0.38, dampingFraction: 0.8)).wrappedValue = .medium
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .medium:
            $gridSize.animation(.spring(response: 0.38, dampingFraction: 0.8)).wrappedValue = .large
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .large:
            break
        }
    }
    
    private func zoomOutGrid() {
        switch gridSize {
        case .large:
            $gridSize.animation(.spring(response: 0.38, dampingFraction: 0.8)).wrappedValue = .medium
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .medium:
            $gridSize.animation(.spring(response: 0.38, dampingFraction: 0.8)).wrappedValue = .compact
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .compact:
            break
        }
    }
    
    // MARK: - List Mode
    
    @ViewBuilder
    private func listContent(folders: [MediaItem], pictures: [MediaItem]) -> some View {
        ScrollViewReader { proxy in
            List {
                if !folders.isEmpty {
                    Section(String(localized: .Strings.gallerySectionSubfoldersCount(folders.count))) {
                        ForEach(folders) { subfolder in
                            Button {
                                onSelectFolder?(subfolder)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder.fill")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(subfolder.name)
                                            .foregroundColor(.primary)
                                        if let d = subfolder.formattedDate {
                                            Text(d)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .id("topOfList")
                }
                
                if !pictures.isEmpty {
                    Section(String(localized: mediaSectionHeader(for: pictures.count))) {
                        ForEach(pictures) { pic in
                            Button {
                                if isSelectionMode {
                                    toggleSelection(for: pic)
                                } else {
                                    onSelectPicture(pic, pictures)
                                }
                            } label: {
                                MediaListRowCell(
                                    manager: manager,
                                    item: pic,
                                    isSelected: selectedItems.contains(pic),
                                    isSelectionMode: isSelectionMode
                                )
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                LongPressGesture().onEnded { _ in
                                    if !isSelectionMode {
                                        withAnimation {
                                            isSelectionMode = true
                                            selectedItems.insert(pic)
                                        }
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }
                                }
                            )
                        }
                    }
                    .id(folders.isEmpty ? "topOfList" : "picturesSection")
                }
            }
            .id(currentDirectoryID)
            .onChange(of: currentDirectoryID) { _, _ in
                proxy.scrollTo("topOfList", anchor: .top)
            }
            .onChange(of: manager.isLoading) { wasLoading, isLoading in
                if wasLoading && !isLoading {
                    proxy.scrollTo("topOfList", anchor: .top)
                }
            }
            .refreshable {
                if let folder = manager.selectedFolder {
                    await manager.selectAndLoadFolder(folder)
                } else {
                    await manager.refreshSharesAndFolders()
                }
            }
        }
    }
    
    // MARK: - Batch Selection Actions
    
    private func toggleSelection(for item: MediaItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func toggleAllSelection(for pictures: [MediaItem]) {
        if selectedItems.count == pictures.count && !pictures.isEmpty {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(pictures)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    private func batchToggleFavorites() {
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
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    /// Cancels any currently active batch save or batch share operation.
    private func cancelBatchTask() {
        batchTask?.cancel()
        batchTask = nil
        isBatchProcessing = false
        batchProgressMessage = nil
    }
    
    /// Exports selected media files to the user's Photos library concurrently (up to 3 parallel workers).
    private func batchSaveToPhotos() {
        let items = Array(selectedItems)
        guard !items.isEmpty else { return }
        isBatchProcessing = true
        batchTask?.cancel()
        
        batchTask = Task { @MainActor in
            var completedCount = 0
            var savedCount = 0
            var failedCount = 0
            let total = items.count
            
            // Bounded concurrency pool (up to 3 parallel downloads to maximize network throughput without saturating memory)
            await withTaskGroup(of: Bool.self) { group in
                var iterator = items.makeIterator()
                let maxConcurrent = 3
                
                // Seed initial workers
                for _ in 0..<min(maxConcurrent, total) {
                    if let nextItem = iterator.next() {
                        group.addTask { [manager = self.manager] in
                            await self.saveSingleMediaItemToPhotos(nextItem, manager: manager)
                        }
                    }
                }
                
                // As each worker finishes, update progress and schedule the next queued item
                while let success = await group.next() {
                    guard !Task.isCancelled else { break }
                    completedCount += 1
                    if success {
                        savedCount += 1
                    } else {
                        failedCount += 1
                    }
                    batchProgressMessage = String(localized: .Strings.galleryBatchSavingProgress(completedCount, total))
                    
                    if let nextItem = iterator.next() {
                        group.addTask { [manager = self.manager] in
                            await self.saveSingleMediaItemToPhotos(nextItem, manager: manager)
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
                    batchStatusToast = String(localized: "Saved \(savedCount) of \(total) items to Photos", comment: "Toast message when batch save completes with partial failures")
                } else if failedCount > 0 && savedCount == 0 {
                    batchStatusToast = String(localized: "Failed to save items to Photos", comment: "Toast message when batch save fails completely")
                } else {
                    batchStatusToast = String(localized: .Strings.galleryBatchSavedToPhotos(savedCount))
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
    
    private nonisolated func saveSingleMediaItemToPhotos(_ item: MediaItem, manager: SMBDirectManager) async -> Bool {
        do {
            if item.isVideo {
                let localURL = try await manager.fetchVideoURL(for: item)
                try await PhotoLibrarySaver.saveVideoToPhotos(at: localURL)
            } else {
                guard let image = await manager.downloadImage(for: item) else {
                    return false
                }
                try await PhotoLibrarySaver.saveImageToPhotos(image)
            }
            return true
        } catch {
            AppLog.photos.error("Failed to save \(item.name, privacy: .private): \(error.localizedDescription)")
            return false
        }
    }
    
    /// Prepares selected media items for the system share sheet concurrently.
    private func batchShare() {
        let items = Array(selectedItems)
        guard !items.isEmpty else { return }
        isBatchProcessing = true
        batchProgressMessage = String(localized: .Strings.galleryBatchPreparingShare)
        batchTask?.cancel()
        
        batchTask = Task { @MainActor in
            var shareables: [Any] = []
            let total = items.count
            var completedCount = 0
            
            // Use bounded concurrent workers to fetch and prepare shareables while preserving selection order
            await withTaskGroup(of: (Int, Any?).self) { group in
                let itemQueue = Array(items.enumerated())
                var queueIndex = 0
                let maxConcurrent = 3
                
                for _ in 0..<min(maxConcurrent, total) {
                    if queueIndex < itemQueue.count {
                        let (idx, item) = itemQueue[queueIndex]
                        queueIndex += 1
                        group.addTask { [manager = self.manager] in
                            let result = await self.prepareSingleItemForShare(item, manager: manager)
                            return (idx, result)
                        }
                    }
                }
                
                var indexedResults: [(Int, Any)] = []
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
                            let nextResult = await self.prepareSingleItemForShare(nextItem, manager: manager)
                            return (nextIdx, nextResult)
                        }
                    }
                }
                
                indexedResults.sort { $0.0 < $1.0 }
                shareables = indexedResults.map { $0.1 }
            }
            
            guard !Task.isCancelled else {
                isBatchProcessing = false
                batchProgressMessage = nil
                return
            }
            
            isBatchProcessing = false
            batchProgressMessage = nil
            
            if !shareables.isEmpty {
                self.shareSheetItems = shareables
            }
        }
    }
    
    private nonisolated func prepareSingleItemForShare(_ item: MediaItem, manager: SMBDirectManager) async -> Any? {
        if item.isVideo {
            return try? await manager.fetchVideoURL(for: item)
        } else {
            return await manager.downloadImage(for: item)
        }
    }
}
