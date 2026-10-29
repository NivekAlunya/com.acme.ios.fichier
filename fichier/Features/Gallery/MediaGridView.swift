//
//  MediaGridView.swift
//  fichier
//

import SwiftUI

struct MediaGridView: View {
    var manager: SMBDirectManager
    var onSelectFolder: ((SMBItem) -> Void)? = nil
    var onStartSlideshow: (() -> Void)? = nil
    let onSelectPicture: (SMBItem) -> Void
    
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
    @State private var selectedItems: Set<SMBItem> = []
    @State private var isBatchProcessing = false
    @State private var batchProgressMessage: String?
    @State private var batchStatusToast: String?
    @State private var shareSheetItems: [Any]?
    @State private var showingSettings = false
    
    private var currentDirectoryID: String {
        manager.selectedFolder?.id ?? "root"
    }
    
    // MARK: - Filtered and Sorted Data
    
    private var filteredFolders: [SMBItem] {
        let list = searchText.isEmpty ? manager.currentFolders : manager.currentFolders.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        return sortItems(list)
    }
    
    private var filteredPictures: [SMBItem] {
        var list = searchText.isEmpty ? manager.pictures : manager.pictures.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        if showFavoritesOnly {
            list = list.filter { FavoritesManager.shared.isFavorite($0) }
        }
        switch mediaFilter {
        case .all:
            break
        case .photos:
            list = list.filter { !$0.isVideo }
        case .videos:
            list = list.filter { $0.isVideo }
        }
        return sortItems(list)
    }
    
    private var mediaSectionTitle: String {
        switch mediaFilter {
        case .all: return String(localized: .Strings.galleryTitleMedia)
        case .photos: return String(localized: .Strings.galleryFilterPhotos)
        case .videos: return String(localized: .Strings.galleryFilterVideos)
        }
    }
    
    private var mediaSectionHeader: LocalizedStringResource {
        let count = filteredPictures.count
        switch mediaFilter {
        case .all: return .Strings.gallerySectionMediaCount(count)
        case .photos: return .Strings.gallerySectionPhotosCount(count)
        case .videos: return .Strings.gallerySectionVideosCount(count)
        }
    }
    
    private func sortItems(_ items: [SMBItem]) -> [SMBItem] {
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
                } else if !searchText.isEmpty && filteredPictures.isEmpty && filteredFolders.isEmpty {
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
                        gridContent
                    case .list:
                        listContent
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
                    Button(selectedItems.count == filteredPictures.count && !filteredPictures.isEmpty ? .Strings.galleryButtonDeselectAll : .Strings.galleryButtonSelectAll) {
                        toggleAllSelection()
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
                        if !filteredPictures.isEmpty {
                            Button(.Strings.galleryButtonSelect) {
                                withAnimation {
                                    isSelectionMode = true
                                }
                            }
                        }
                        
                        // Slideshow trigger & duration menu
                        if !filteredPictures.isEmpty {
                            Menu {
                                Button {
                                    onStartSlideshow?()
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
                                onStartSlideshow?()
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
    }
    
    // MARK: - Grid Mode
    
    private var gridContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id("topOfGrid")
                
                VStack(alignment: .leading, spacing: 16) {
                    if !filteredFolders.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(.Strings.gallerySectionSubfoldersCount(filteredFolders.count))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 8)], spacing: 8) {
                                ForEach(filteredFolders) { subfolder in
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
                    
                    if !filteredPictures.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(mediaSectionHeader)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(sortOption.localizedTitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            
                            LazyVGrid(columns: gridColumns, spacing: 10) {
                                ForEach(filteredPictures) { pic in
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
                                            onSelectPicture(pic)
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
                    } else if !filteredFolders.isEmpty {
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
    
    private var listContent: some View {
        ScrollViewReader { proxy in
            List {
                if !filteredFolders.isEmpty {
                    Section(String(localized: .Strings.gallerySectionSubfoldersCount(filteredFolders.count))) {
                        ForEach(filteredFolders) { subfolder in
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
                
                if !filteredPictures.isEmpty {
                    Section(String(localized: mediaSectionHeader)) {
                        ForEach(filteredPictures) { pic in
                            Button {
                                if isSelectionMode {
                                    toggleSelection(for: pic)
                                } else {
                                    onSelectPicture(pic)
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
                    .id(filteredFolders.isEmpty ? "topOfList" : "picturesSection")
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
    
    private func toggleSelection(for item: SMBItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func toggleAllSelection() {
        if selectedItems.count == filteredPictures.count && !filteredPictures.isEmpty {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(filteredPictures)
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
    
    private func batchSaveToPhotos() {
        let items = Array(selectedItems)
        guard !items.isEmpty else { return }
        isBatchProcessing = true
        
        Task {
            var savedCount = 0
            for (idx, item) in items.enumerated() {
                batchProgressMessage = String(localized: .Strings.galleryBatchSavingProgress(idx + 1, items.count))
                do {
                    if item.isVideo {
                        let localURL = try await manager.fetchVideoURL(for: item)
                        try await PhotoLibrarySaver.saveVideoToPhotos(at: localURL)
                    } else {
                        if let image = await manager.downloadImage(for: item) {
                            try await PhotoLibrarySaver.saveImageToPhotos(image)
                        }
                    }
                    savedCount += 1
                } catch {
                    print("⚠️ [Photos] Failed to save \(item.name): \(error)")
                }
            }
            
            isBatchProcessing = false
            batchProgressMessage = nil
            withAnimation {
                batchStatusToast = String(localized: .Strings.galleryBatchSavedToPhotos(savedCount))
                isSelectionMode = false
                selectedItems.removeAll()
            }
            
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation {
                batchStatusToast = nil
            }
        }
    }
    
    private func batchShare() {
        let items = Array(selectedItems)
        guard !items.isEmpty else { return }
        isBatchProcessing = true
        batchProgressMessage = String(localized: .Strings.galleryBatchPreparingShare)
        
        Task {
            var shareables: [Any] = []
            for item in items {
                if item.isVideo {
                    if let localURL = try? await manager.fetchVideoURL(for: item) {
                        shareables.append(localURL)
                    }
                } else {
                    if let image = await manager.downloadImage(for: item) {
                        shareables.append(image)
                    }
                }
            }
            isBatchProcessing = false
            batchProgressMessage = nil
            
            if !shareables.isEmpty {
                self.shareSheetItems = shareables
            }
        }
    }
}
