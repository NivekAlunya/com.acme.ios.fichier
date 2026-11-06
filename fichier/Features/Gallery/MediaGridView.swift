//
//  MediaGridView.swift
//  fichier
//

import SwiftUI
import Foundation
import OSLog

/// A primary gallery container view responsible for browsing, sorting, filtering, and batch-managing
/// media items (photos, videos, documents) stored either locally, in iCloud, or on remote SMB network shares.
///
/// ### Architecture & Concurrency Overview
/// - **Actor Isolation**: Conforms to SwiftUI `View`, implicitly bound to `@MainActor`. All UI-driven state mutations
///   and gesture handling occur strictly on the main thread.
/// - **Swift 6 Concurrency**: Batch export and share preparation execute within bounded asynchronous worker pools
///   using `withTaskGroup`, offloading network and disk I/O while strictly honoring task cancellation.
/// - **State Synchronization**: Automatically reflects live changes from `StorageLocationManager` (`@Observable`)
///   and persists layout preferences across app launches via `@AppStorage`.
struct MediaGridView: View {
    
    // MARK: - Injected Dependencies
    
    /// The centralized storage and connectivity manager responsible for folder enumeration,
    /// thumbnail caching, file downloads, and remote share traversal.
    var manager: StorageLocationManager
    
    /// Optional closure invoked when the user selects a subfolder to navigate into.
    /// If `nil`, the view defaults to driving folder navigation directly through `manager.selectAndLoadFolder(_:)`.
    var onSelectFolder: ((MediaItem) -> Void)?
    
    /// Optional closure invoked when starting a fullscreen slideshow presentation with the current set of filtered pictures.
    var onStartSlideshow: (([MediaItem]) -> Void)?
    
    /// Callback closure invoked when an individual picture is tapped to open fullscreen viewer,
    /// providing the tapped item alongside the contextual list of all sibling pictures for swiping.
    let onSelectPicture: (MediaItem, [MediaItem]) -> Void
    
    // MARK: - Environment & Persistent Settings
    
    /// Horizontal size class used to conditionally adapt toolbar actions and modal sheets for compact (iPhone) vs regular (iPad/Mac) displays.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    /// User preference determining whether files are presented as an adaptive grid or a vertical scroll list.
    @AppStorage("gallery_view_mode") private var viewMode: ViewMode = .grid
    
    /// Active sort descriptor applied to folder and media item lists.
    @AppStorage("gallery_sort_option") private var sortOption: SortOption = .nameAsc
    
    /// Grid density setting controlling thumbnail sizing and adaptive column bounds in grid mode.
    @AppStorage("gallery_grid_size") private var gridSize: GridSize = .medium
    
    /// Auto-advance timer interval in seconds for slideshow playback.
    @AppStorage("slideshow_timer_interval") private var slideshowInterval: Double = 3.0
    
    /// Visual transition animation applied between consecutive slides during slideshow playback.
    @AppStorage("slideshow_transition_style") private var transitionStyle: SlideshowTransitionStyle = .slide
    
    // MARK: - Search & Gesture State
    
    /// Live search query string bound to the SwiftUI `.searchable` modifier.
    @State private var searchText = ""
    
    /// Tracks the magnification scale at the end of the previous discrete gesture step to compute relative zoom ratios.
    @State private var lastPinchScale: CGFloat = 1.0
    
    /// Timestamp of the most recent discrete zoom step, used to debounce rapid pinch gesture events.
    @State private var lastPinchTime: Date = .distantPast
    
    // MARK: - Pinch Gesture Configuration
    
    /// Magnification ratio threshold above which a pinch-out gesture triggers a step up in thumbnail size (or list-to-grid transition).
    private static let pinchZoomInRatioThreshold: CGFloat = 1.45
    
    /// Magnification ratio threshold below which a pinch-in gesture triggers a step down in thumbnail size (or compact-grid-to-list transition).
    private static let pinchZoomOutRatioThreshold: CGFloat = 0.65
    
    /// Minimum time delay (in seconds) required between consecutive discrete pinch-to-zoom step evaluations, preventing visual stutter.
    private static let pinchCooldownSeconds: TimeInterval = 0.30
    
    // MARK: - Filtering & Batch Selection State
    
    /// Flag indicating whether the media list should be restricted exclusively to items marked as favorites.
    @State private var showFavoritesOnly = false
    
    /// Active media category filter applied to display items (e.g. photos, videos, documents, or all).
    @State private var mediaFilter: MediaFilter = .all
    
    /// Toggles multi-selection mode for performing batch operations (favoriting, saving to Photos, or sharing).
    @State private var isSelectionMode = false
    
    /// The set of uniquely selected `MediaItem` instances currently highlighted in selection mode.
    @State private var selectedItems: Set<MediaItem> = []
    
    /// Flag indicating that a background batch export or share preparation task is currently executing.
    @State private var isBatchProcessing = false
    
    /// User-facing status string displayed in the selection bottom bar indicating current batch progress (e.g., "Saving (2/10)").
    @State private var batchProgressMessage: String?
    
    /// Transient status message displayed inside an animated toast capsule upon batch operation completion.
    @State private var batchStatusToast: String?
    
    /// Active structured asynchronous task handle executing batch processing, cancellable by user action or view dismissal.
    @State private var batchTask: Task<Void, Never>?
    
    /// Holds the prepared shareable items (images/URLs) passed to `MediaActivityShareSheet` when ready to present.
    @State private var shareSheetItems: [Any]?
    
    /// Controls presentation of the application settings sheet on compact size classes.
    @State private var showingSettings = false
    
    /// Unique identity token incremented or refreshed to force complete invalidation and reload of visible thumbnail cells.
    @State private var thumbnailReloadToken = UUID()
    
    // MARK: - Directory Identification
    
    /// Stable identifier representing the current browsing scope, used to reset scroll positions when switching folders.
    private var currentDirectoryID: String {
        manager.selectedFolder?.id ?? "root"
    }
    
    // MARK: - Filtered and Sorted Data Pipeline
    
    /// Applies search filtering, favorites filtering, media kind classification, and ordering to the current folder's contents.
    ///
    /// - Returns: A tuple containing sorted subfolders and sorted media items ready for presentation.
    ///
    /// ### Complex Logic Breakdown:
    /// 1. **Search**: Case-insensitive substring matching using `localizedCaseInsensitiveContains` on folder and media item names.
    /// 2. **Favorites Discrimination**: Queries the high-performance `FavoritesManager` cache when `showFavoritesOnly` is active.
    /// 3. **Type Segregation**: Categorizes items into photos, videos, or documents based on MIME type and file extension flags.
    /// 4. **Natural Ordering**: Applies `sortItems(_:)` to ensure natural alphanumeric sorting (e.g. "File 2" before "File 10").
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
            listPictures = listPictures.filter(\.isImage)
        case .videos:
            listPictures = listPictures.filter { $0.isVideo }
        case .documents:
            listPictures = listPictures.filter { $0.isPDF }
        }
        let sortedPictures = sortItems(listPictures)
        return (sortedFolders, sortedPictures)
    }
    
    /// Produces a localized section header string dynamically reflecting the active media filter and count.
    ///
    /// - Parameter count: The number of media items present in the section.
    /// - Returns: A localized string resource configured with the item count.
    private func mediaSectionHeader(for count: Int) -> LocalizedStringResource {
        switch mediaFilter {
        case .all: return .Strings.gallerySectionMediaCount(count)
        case .photos: return .Strings.gallerySectionPhotosCount(count)
        case .videos: return .Strings.gallerySectionVideosCount(count)
        case .documents: return LocalizedStringResource("gallery_section_documents_count", defaultValue: "\(count) Documents")
        }
    }
    
    /// Sorts an array of `MediaItem` instances according to the user's selected `sortOption`.
    ///
    /// - Parameter items: The unsorted media items.
    /// - Returns: The stably sorted media items.
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
    
    /// Dynamic grid layout specification computed from the active `gridSize`.
    /// Uses adaptive sizing bounded between `minDimension` and `1.45 * minDimension` to balance row alignment and screen width.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: gridSize.minDimension, maximum: gridSize.minDimension * 1.45), spacing: 10)]
    }
    
    /// Accessibility label for the parent folder navigation button, dynamically reflecting the parent folder name when available.
    /// Extracted as a dedicated property to avoid complex nested expression evaluation inside the SwiftUI toolbar ViewBuilder.
    private var parentFolderAccessibilityLabel: String {
        if let parentName = manager.parentFolder?.name {
            String(localized: "Navigate to parent folder: \(parentName)", comment: "Accessibility label for parent folder button")
        } else {
            String(localized: "Parent folder", comment: "Accessibility label for parent folder button")
        }
    }
    
    // MARK: - Body View Hierarchy
    
    var body: some View {
        let (displayFolders, displayPictures) = filterAndSortData()
        let hasImages = displayPictures.contains(where: \.isImage)
        
        ZStack(alignment: .bottom) {
            Group {
                if manager.pictures.isEmpty && manager.currentFolders.isEmpty {
                    MediaGridEmptyStateView(
                        isLoading: manager.isLoading,
                        errorMessage: manager.errorMessage,
                        searchText: searchText,
                        selectedFolderName: manager.selectedFolder?.name,
                        hasSelectedFolder: manager.selectedFolder != nil,
                        onRetry: {
                            if let folder = manager.selectedFolder {
                                Task { await manager.selectAndLoadFolder(folder) }
                            }
                        }
                    )
                } else if !searchText.isEmpty && displayPictures.isEmpty && displayFolders.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    Group {
                        switch viewMode {
                        case .grid:
                            MediaGridModeView(
                                manager: manager,
                                folders: displayFolders,
                                pictures: displayPictures,
                                gridColumns: gridColumns,
                                gridSize: gridSize,
                                sortOption: sortOption,
                                isSelectionMode: isSelectionMode,
                                selectedItems: selectedItems,
                                currentDirectoryID: currentDirectoryID,
                                onNavigateToFolder: { navigateToFolder($0) },
                                onSelectPicture: { onSelectPicture($0, $1) },
                                onToggleSelection: { toggleSelection(for: $0) },
                                onEnterSelectionMode: { item in
                                    withAnimation {
                                        isSelectionMode = true
                                        selectedItems.insert(item)
                                    }
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                },
                                onRefresh: {
                                    if let folder = manager.selectedFolder {
                                        await manager.selectAndLoadFolder(folder)
                                    } else {
                                        await manager.refreshSharesAndFolders()
                                    }
                                }
                            )
                            .simultaneousGesture(pinchGesture)
                            .transition(.opacity)
                        case .list:
                            MediaListModeView(
                                manager: manager,
                                folders: displayFolders,
                                pictures: displayPictures,
                                isSelectionMode: isSelectionMode,
                                selectedItems: selectedItems,
                                currentDirectoryID: currentDirectoryID,
                                onNavigateToFolder: { navigateToFolder($0) },
                                onSelectPicture: { onSelectPicture($0, $1) },
                                onToggleSelection: { toggleSelection(for: $0) },
                                onEnterSelectionMode: { item in
                                    withAnimation {
                                        isSelectionMode = true
                                        selectedItems.insert(item)
                                    }
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                },
                                onRefresh: {
                                    if let folder = manager.selectedFolder {
                                        await manager.selectAndLoadFolder(folder)
                                    } else {
                                        await manager.refreshSharesAndFolders()
                                    }
                                }
                            )
                            .transition(.opacity)
                        }
                    }
                    .id(thumbnailReloadToken)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: viewMode)
            
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
            
            // Status Toast Banner (e.g. Saved to Photos notification)
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
                        Button {
                            if let parent = manager.parentFolder {
                                navigateToFolder(parent)
                            }
                        } label: {
                            Image(systemName: "arrow.up.folder")
                                .fontWeight(.semibold)
                                .foregroundColor(manager.parentFolder != nil ? .blue : .secondary.opacity(0.35))
                        }
                        .tint(.blue)
                        .disabled(manager.parentFolder == nil)
                        .accessibilityLabel(parentFolderAccessibilityLabel)
                        
                        if !displayPictures.isEmpty {
                            Button {
                                withAnimation {
                                    isSelectionMode = true
                                }
                            } label: {
                                Image(systemName: viewMode.selectionIconName)
                            }
                            .accessibilityLabel(.Strings.galleryButtonSelect)
                        }
                        
                        // Slideshow trigger & duration menu
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
                        .disabled(!hasImages)
                        
                        // Unified View, Sort & Grid Size Menu
                        Menu {
                            Section(.Strings.galleryMenuLayout) {
                                Picker(.Strings.galleryMenuViewMode, selection: $viewMode.animation(.spring(response: 0.38, dampingFraction: 0.8))) {
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
                            
                            #if DEBUG
                            Section("Debug") {
                                Button(role: .destructive) {
                                    Task {
                                        await manager.invalidateCurrentFolderThumbnails()
                                        thumbnailReloadToken = UUID()
                                    }
                                } label: {
                                    Label("Invalidate Folder Thumbnails", systemImage: "arrow.triangle.2.circlepath.circle")
                                }
                            }
                            #endif
                            
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
                    }.padding(.horizontal)
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
                #if DEBUG
                // Cmd+Option+R: Invalidate thumbnails for current folder
                Button("") {
                    Task {
                        await manager.invalidateCurrentFolderThumbnails()
                        thumbnailReloadToken = UUID()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                #endif
                
                // Space: Start slideshow of pictures in current folder
                Button("") {
                    if hasImages {
                        onStartSlideshow?(displayPictures)
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!hasImages)
                
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
    
    // MARK: - Navigation Helpers
    
    /// Navigates the application into the specified folder.
    /// Prefers the parent-injected `onSelectFolder` closure if supplied, or falls back to invoking `manager.selectAndLoadFolder(_:)`.
    ///
    /// - Parameter folder: The destination folder `MediaItem`.
    private func navigateToFolder(_ folder: MediaItem) {
        if let onSelectFolder {
            onSelectFolder(folder)
        } else {
            Task {
                await manager.selectAndLoadFolder(folder)
            }
        }
    }
    
    // MARK: - Pinch Gesture & Zoom Mechanics
    
    /// Simultaneous magnification gesture enabling fluid scaling between thumbnail sizes and list view.
    ///
    /// ### Complex Code Breakdown:
    /// - **Delta Ratio Calculation**: Computes `ratio = scale / lastPinchScale` to measure incremental velocity and spread
    ///   rather than absolute magnification relative to gesture start.
    /// - **Debounce Cooldown**: Enforces `pinchCooldownSeconds (300ms)` threshold to prevent rapid flickering between
    ///   intermediate grid steps during a continuous gesture stroke.
    /// - **Discrete Stage Progression**: Transitions through `List <-> Compact Grid <-> Medium Grid <-> Large Grid`.
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let scale = value.magnification
                let ratio = scale / lastPinchScale
                
                let now = Date()
                guard now.timeIntervalSince(lastPinchTime) >= Self.pinchCooldownSeconds else { return }
                
                // Pinch out (fingers spreading) -> enlarge thumbnails / switch from list to compact grid
                if ratio > Self.pinchZoomInRatioThreshold {
                    zoomIn()
                    lastPinchScale = scale
                    lastPinchTime = now
                }
                // Pinch in (fingers pinching together) -> shrink thumbnails / switch from compact grid to list
                else if ratio < Self.pinchZoomOutRatioThreshold {
                    zoomOut()
                    lastPinchScale = scale
                    lastPinchTime = now
                }
            }
            .onEnded { _ in
                lastPinchScale = 1.0
            }
    }
    
    /// Steps up the zoom level: if currently in List mode, switches to Compact Grid;
    /// if in Grid mode, cycles from Compact -> Medium -> Large with haptic feedback.
    private func zoomIn() {
        if viewMode == .list {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                viewMode = .grid
                gridSize = .compact
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
        
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
    
    /// Steps down the zoom level: if in Grid mode, cycles from Large -> Medium -> Compact,
    /// and from Compact transitions to List mode; if in List mode, remains unchanged.
    private func zoomOut() {
        if viewMode == .list {
            return
        }
        
        switch gridSize {
        case .large:
            $gridSize.animation(.spring(response: 0.38, dampingFraction: 0.8)).wrappedValue = .medium
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .medium:
            $gridSize.animation(.spring(response: 0.38, dampingFraction: 0.8)).wrappedValue = .compact
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .compact:
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                viewMode = .list
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
    
    // MARK: - Batch Selection Actions
    
    /// Toggles the selection status of a single media item, triggering light haptic feedback.
    ///
    /// - Parameter item: The `MediaItem` to add to or remove from `selectedItems`.
    private func toggleSelection(for item: MediaItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    /// Selects all visible media items if not already all selected; otherwise, clears the selection set.
    ///
    /// - Parameter pictures: The currently visible array of pictures subject to selection.
    private func toggleAllSelection(for pictures: [MediaItem]) {
        if selectedItems.count == pictures.count && !pictures.isEmpty {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(pictures)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    /// Toggles the favorite status across all selected items.
    /// If all selected items are already marked as favorites, unmarks all of them; otherwise, marks any un-favorited items as favorite.
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
    
    /// Cancels any currently active batch save or batch share operation and resets progress flags.
    private func cancelBatchTask() {
        batchTask?.cancel()
        batchTask = nil
        isBatchProcessing = false
        batchProgressMessage = nil
    }
    
    // MARK: - Batch Export to Photos
    
    /// Exports selected media files to the user's Photos library concurrently using a bounded worker pool.
    ///
    /// ### Complex Concurrency Architecture:
    /// - **Bounded Worker Concurrency**: Uses `withTaskGroup` with a maximum concurrency limit (`maxConcurrent = 3`).
    ///   Spawning unbounded download tasks over SMB or local networks would cause TCP socket starvation and high memory
    ///   consumption from simultaneous image decoding.
    /// - **Sliding Window Dispatch**: Seeds 3 initial workers. As each worker finishes via `group.next()`, progress counters
    ///   are updated and the next item is dequeued from `iterator.next()`.
    /// - **Cooperative Task Cancellation**: Polls `Task.isCancelled` at each stage to ensure immediate response if the user taps Cancel.
    /// - **Transient Toast Timer**: Displays a result summary in a top capsule banner and schedules an auto-dismissing
    ///   timer using structured `Task.sleep(for: .seconds(2.5))`.
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
                            await Self.saveSingleMediaItemToPhotos(nextItem, manager: manager)
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
                            await Self.saveSingleMediaItemToPhotos(nextItem, manager: manager)
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
    
    /// Saves an individual media item (image or video) to the system Photos library.
    ///
    /// Declared `static` to ensure no implicit capture of the enclosing SwiftUI `View` struct
    /// inside concurrent `@Sendable` task closures.
    ///
    /// - Parameters:
    ///   - item: The `MediaItem` representing the photo or video to export.
    ///   - manager: The `StorageLocationManager` instance used to fetch the remote file or image data.
    /// - Returns: `true` if the media item was successfully saved to Photos; otherwise, `false`.
    private static func saveSingleMediaItemToPhotos(_ item: MediaItem, manager: StorageLocationManager) async -> Bool {
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
    
    // MARK: - Batch Share Preparation
    
    /// Prepares selected media items for the system share sheet concurrently while strictly preserving selection order.
    ///
    /// ### Complex Code Breakdown:
    /// - **Order Preservation**: Each download task carries an enumerated index `(idx, item)`. Because parallel downloads
    ///   may finish out-of-order, results are collected into `indexedResults: [(Int, Any)]` and stably sorted by index
    ///   prior to presenting `UIActivityViewController`.
    /// - **Bounded Worker Concurrency**: Employs the same sliding window pattern as `batchSaveToPhotos()` (`maxConcurrent = 3`)
    ///   to avoid memory bloat when buffering multiple full-resolution images or videos simultaneously.
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
                
                for _ in 0..<min(maxConcurrent, total) where queueIndex < itemQueue.count {
                    let (idx, item) = itemQueue[queueIndex]
                    queueIndex += 1
                    group.addTask { [manager = self.manager] in
                        let result = await Self.prepareSingleItemForShare(item, manager: manager)
                        return (idx, result)
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
                            let nextResult = await Self.prepareSingleItemForShare(nextItem, manager: manager)
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
    
    /// Prepares an individual media item for sharing by downloading its image or fetching its local video URL.
    ///
    /// Declared `static` to eliminate `self` captures within parallel task group operations.
    ///
    /// - Parameters:
    ///   - item: The `MediaItem` to prepare for sharing.
    ///   - manager: The `StorageLocationManager` instance used to resolve the media resource.
    /// - Returns: A `UIImage` for photos, a `URL` for videos, or `nil` if preparation failed.
    private static func prepareSingleItemForShare(_ item: MediaItem, manager: StorageLocationManager) async -> Any? {
        if item.isVideo {
            return try? await manager.fetchVideoURL(for: item)
        } else {
            return await manager.downloadImage(for: item)
        }
    }
}
