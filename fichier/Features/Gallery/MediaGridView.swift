//
//  MediaGridView.swift
//  fichier
//

import SwiftUI
import Foundation
import Wappn
import FichierKit

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
    
    /// Optional closure invoked when the user selects a subfolder to navigate into.
    /// If `nil`, the view defaults to driving folder navigation directly through `manager.selectAndLoadFolder(_:)`.
    var onSelectFolder: ((MediaItem) -> Void)?
    
    /// Optional closure invoked when starting a fullscreen slideshow presentation with the current set of filtered pictures.
    var onStartSlideshow: (([MediaItem]) -> Void)?
    
    /// Callback closure invoked when an individual picture is tapped to open fullscreen viewer,
    /// providing the tapped item alongside the contextual list of all sibling pictures for swiping.
    let onSelectPicture: (MediaItem, [MediaItem]) -> Void

    @State private var viewModel: MediaGridViewModel

    init(
        manager: StorageLocationManager,
        onSelectFolder: ((MediaItem) -> Void)? = nil,
        onStartSlideshow: (([MediaItem]) -> Void)? = nil,
        onSelectPicture: @escaping (MediaItem, [MediaItem]) -> Void
    ) {
        self.onSelectFolder = onSelectFolder
        self.onStartSlideshow = onStartSlideshow
        self.onSelectPicture = onSelectPicture
        // Note: SwiftUI view structs are transient and re-evaluated during parent updates.
        // While State(initialValue:) evaluates on every init, @State retains only the
        // original state object across renders and discards transient allocations.
        _viewModel = State(initialValue: MediaGridViewModel(manager: manager))
    }
    
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

    // MARK: - Filtered and Sorted Data Pipeline
    
    @ViewBuilder
    private var slideshowDurationSection: some View {
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
    }

    @ViewBuilder
    private var filterMenuSection: some View {
        Section(.Strings.galleryMenuFilter) {
            Picker(.Strings.galleryPickerMediaType, selection: $viewModel.mediaFilter) {
                ForEach(MediaFilter.allCases) { filter in
                    Label(filter.localizedTitle, systemImage: filter.iconName).tag(filter)
                }
            }

            Toggle(isOn: $viewModel.showFavoritesOnly) {
                Label(.Strings.galleryFilterFavoritesOnly, systemImage: "heart.fill")
            }
        }
    }

    private func beginRenameSelected() {
        guard viewModel.selectedItems.count == 1, let item = viewModel.selectedItems.first else { return }
        viewModel.itemToRename = item
        viewModel.renameText = item.name
    }

    private func filterAndSortData() -> (folders: [MediaItem], pictures: [MediaItem]) {
        viewModel.filterAndSortData(sortOption: sortOption)
    }
    
    private func mediaSectionHeader(for count: Int) -> LocalizedStringResource {
        viewModel.mediaSectionHeader(for: count)
    }
    
    /// Dynamic grid layout specification computed from the active `gridSize`.
    /// Uses adaptive sizing bounded between `minDimension` and `1.45 * minDimension` to balance row alignment and screen width.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: gridSize.minDimension, maximum: gridSize.minDimension * 1.45), spacing: 10)]
    }
    
    private var parentFolderAccessibilityLabel: String {
        viewModel.parentFolderAccessibilityLabel
    }
    
    // MARK: - Body View Hierarchy
    
    var body: some View {
        let (displayFolders, displayPictures) = filterAndSortData()
        let hasImages = displayPictures.contains(where: \.isImage)
        
        ZStack(alignment: .bottom) {
            Group {
                if viewModel.manager.pictures.isEmpty && viewModel.manager.currentFolders.isEmpty {
                    MediaGridEmptyStateView(
                        isLoading: viewModel.manager.isLoading,
                        errorMessage: viewModel.manager.errorMessage,
                        searchText: viewModel.searchText,
                        selectedFolderName: viewModel.manager.selectedFolder?.name,
                        hasSelectedFolder: viewModel.manager.selectedFolder != nil,
                        onRetry: {
                            if let folder = viewModel.manager.selectedFolder {
                                Task { await viewModel.manager.selectAndLoadFolder(folder) }
                            }
                        }
                    )
                } else if !viewModel.searchText.isEmpty && displayPictures.isEmpty && displayFolders.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchText)
                } else {
                    Group {
                        switch viewMode {
                        case .grid:
                            MediaGridModeView(
                                manager: viewModel.manager,
                                folders: displayFolders,
                                pictures: displayPictures,
                                gridColumns: gridColumns,
                                gridSize: gridSize,
                                sortOption: sortOption,
                                isSelectionMode: viewModel.isSelectionMode,
                                selectedItems: viewModel.selectedItems,
                                currentDirectoryID: viewModel.currentDirectoryID,
                                onNavigateToFolder: { navigateToFolder($0) },
                                onSelectPicture: {
                                    AppKeyboardDismissal.dismiss()
                                    onSelectPicture($0, $1)
                                },
                                onToggleSelection: { toggleSelection(for: $0) },
                                onEnterSelectionMode: { item in
                                    withAnimation {
                                        viewModel.isSelectionMode = true
                                        viewModel.selectedItems.insert(item)
                                    }
                                    AppHapticFeedback.medium()
                                },
                                onRefresh: {
                                    if let folder = viewModel.manager.selectedFolder {
                                        await viewModel.manager.selectAndLoadFolder(folder)
                                    } else {
                                        await viewModel.manager.refreshSharesAndFolders()
                                    }
                                },
                                onRequestRename: { item in
                                    viewModel.itemToRename = item
                                    viewModel.renameText = item.name
                                },
                                onRequestMove: { item in
                                    viewModel.itemsPendingMove = [item]
                                },
                                onRequestDelete: { item in
                                    viewModel.itemsPendingDelete = [item]
                                }
                            )
                            #if !os(tvOS)
                            .simultaneousGesture(pinchGesture)
                            #endif
                            .transition(.opacity)
                        case .list:
                            MediaListModeView(
                                manager: viewModel.manager,
                                folders: displayFolders,
                                pictures: displayPictures,
                                isSelectionMode: viewModel.isSelectionMode,
                                selectedItems: viewModel.selectedItems,
                                currentDirectoryID: viewModel.currentDirectoryID,
                                onNavigateToFolder: { navigateToFolder($0) },
                                onSelectPicture: {
                                    AppKeyboardDismissal.dismiss()
                                    onSelectPicture($0, $1)
                                },
                                onToggleSelection: { toggleSelection(for: $0) },
                                onEnterSelectionMode: { item in
                                    withAnimation {
                                        viewModel.isSelectionMode = true
                                        viewModel.selectedItems.insert(item)
                                    }
                                    AppHapticFeedback.medium()
                                },
                                onRefresh: {
                                    if let folder = viewModel.manager.selectedFolder {
                                        await viewModel.manager.selectAndLoadFolder(folder)
                                    } else {
                                        await viewModel.manager.refreshSharesAndFolders()
                                    }
                                },
                                onRequestRename: { item in
                                    viewModel.itemToRename = item
                                    viewModel.renameText = item.name
                                },
                                onRequestMove: { item in
                                    viewModel.itemsPendingMove = [item]
                                },
                                onRequestDelete: { item in
                                    viewModel.itemsPendingDelete = [item]
                                }
                            )
                            #if !os(tvOS)
                            .simultaneousGesture(pinchGesture)
                            #endif
                            .transition(.opacity)
                        }
                    }
                    .id(viewModel.thumbnailReloadToken)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: viewMode)
            
            // Bottom Action Bar when in Selection Mode
            if viewModel.isSelectionMode {
                MediaSelectionBottomBar(
                    selectedCount: viewModel.selectedItems.count,
                    isAllFavorites: !viewModel.selectedItems.isEmpty && viewModel.selectedItems.allSatisfy { FavoritesManager.shared.isFavorite($0) },
                    isProcessing: viewModel.isBatchProcessing,
                    progressMessage: viewModel.batchProgressMessage,
                    showSaveToPhotos: viewModel.manager.currentLocation?.kind != .photos,
                    showFileManagement: viewModel.manager.canManageCurrentFolder,
                    onCancel: { cancelBatchTask() },
                    onToggleFavorite: { batchToggleFavorites() },
                    onSaveToPhotos: { batchSaveToPhotos() },
                    onDownloadToFiles: { batchDownloadToFiles() },
                    onShare: { batchShare() },
                    onMove: {
                        viewModel.itemsPendingMove = Array(viewModel.selectedItems)
                    },
                    onRename: {
                        beginRenameSelected()
                    },
                    onDelete: {
                        viewModel.itemsPendingDelete = Array(viewModel.selectedItems)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .statusToast(message: $viewModel.batchStatusToast)
        .searchable(text: $viewModel.searchText, prompt: .Strings.gallerySearchPrompt)
        .sheet(isPresented: Binding(
            get: { viewModel.shareSheetItems != nil },
            set: { if !$0 { viewModel.shareSheetItems = nil } }
        )) {
            if let shareSheetItems = viewModel.shareSheetItems {
                MediaActivityShareSheet(activityItems: shareSheetItems)
            }
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            AppSettingsView()
        }
        #if !os(tvOS)
        .sheet(isPresented: Binding(
            get: { viewModel.itemsPendingFileExport != nil },
            set: { if !$0 { viewModel.itemsPendingFileExport = nil } }
        )) {
            if let urls = viewModel.itemsPendingFileExport {
                DocumentPickerExportView(urls: urls) { success in
                    viewModel.itemsPendingFileExport = nil
                    if success {
                        withAnimation {
                            viewModel.batchStatusToast = String(localized: .Strings.galleryBatchSavedToFiles(urls.count))
                            viewModel.isSelectionMode = false
                            viewModel.selectedItems.removeAll()
                        }
                        Task {
                            try? await Task.sleep(for: .seconds(2.5))
                            withAnimation {
                                viewModel.batchStatusToast = nil
                            }
                        }
                    }
                }
            }
        }
        #endif
        .sheet(isPresented: Binding(
            get: { viewModel.itemsPendingMove != nil },
            set: { if !$0 { viewModel.itemsPendingMove = nil } }
        )) {
            if let items = viewModel.itemsPendingMove {
                FolderPickerSheetView(
                    manager: viewModel.manager,
                    itemsToMove: items,
                    onMoveTo: { destination in
                        viewModel.itemsPendingMove = nil
                        executeMove(items: items, to: destination)
                    },
                    onDismiss: {
                        viewModel.itemsPendingMove = nil
                    }
                )
            }
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: Binding(
                get: { viewModel.itemsPendingDelete != nil },
                set: { if !$0 { viewModel.itemsPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(deleteConfirmationButtonTitle, role: .destructive) {
                if let items = viewModel.itemsPendingDelete {
                    viewModel.itemsPendingDelete = nil
                    Task {
                        await executeDelete(items: items)
                    }
                }
            }
            Button(.Strings.commonCancel, role: .cancel) {
                viewModel.itemsPendingDelete = nil
            }
        } message: {
            Text(verbatim: deleteConfirmationMessage)
        }
        .alert(
            .Strings.commonNewFolder,
            isPresented: $viewModel.isShowingNewFolderAlert
        ) {
            TextField(String(localized: .Strings.commonFolderName), text: $viewModel.newFolderName)
            Button(.Strings.commonCancel, role: .cancel) {}
            Button(.Strings.commonCreate) {
                executeCreateFolder()
            }
            .disabled(viewModel.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            if let folder = viewModel.manager.selectedFolder {
                let displayName = folder.name.isEmpty ? folder.rootName : folder.name
                Text(.Strings.galleryCreateSubfolderPrompt(displayName))
            }
        }
        .alert(
            viewModel.itemToRename?.isDirectory == true
                ? String(localized: .Strings.galleryRenameFolderTitle)
                : String(localized: .Strings.galleryRenameFileTitle),
            isPresented: Binding(
                get: { viewModel.itemToRename != nil },
                set: { if !$0 { viewModel.itemToRename = nil } }
            )
        ) {
            TextField(String(localized: .Strings.galleryRenameFieldPlaceholder), text: $viewModel.renameText)
            Button(String(localized: .Strings.commonCancel), role: .cancel) {
                viewModel.itemToRename = nil
            }
            Button(String(localized: .Strings.galleryRenameButton)) {
                if let item = viewModel.itemToRename {
                    executeRename(item: item, to: viewModel.renameText)
                }
            }
            .disabled(viewModel.renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.renameText == viewModel.itemToRename?.name)
        } message: {
            if let item = viewModel.itemToRename {
                Text(String(localized: .Strings.galleryRenamePrompt(item.name)))
            }
        }
        .alert(
            .Strings.galleryErrorFileOperationFailed,
            isPresented: Binding(
                get: { viewModel.fileOpErrorMessage != nil },
                set: { if !$0 { viewModel.fileOpErrorMessage = nil } }
            )
        ) {
            Button(.Strings.commonOk, role: .cancel) {}
        } message: {
            if let fileOpErrorMessage = viewModel.fileOpErrorMessage {
                Text(fileOpErrorMessage)
            }
        }
        .toolbar {
            galleryToolbarContent(displayPictures: displayPictures, hasImages: hasImages)
        }
        .task {
            await viewModel.manager.refreshMediaCacheSize()
        }
        .onDisappear {
            viewModel.batchTask?.cancel()
            viewModel.batchTask = nil
        }
        .background {
            // Hardware Keyboard & Remote Shortcuts for iPadOS, macOS, and tvOS
            Group {
                #if DEBUG
                // Cmd+Option+R: Invalidate thumbnails for current folder
                Button("") {
                    Task {
                        await viewModel.manager.invalidateCurrentFolderThumbnails()
                        viewModel.thumbnailReloadToken = UUID()
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
                    if viewModel.isSelectionMode {
                        withAnimation {
                            viewModel.isSelectionMode = false
                            viewModel.selectedItems.removeAll()
                            cancelBatchTask()
                        }
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                // Cmd+A: Select All / Deselect All (when in selection mode)
                Button("") {
                    if viewModel.isSelectionMode {
                        toggleAllSelection(for: displayPictures)
                    } else if !displayPictures.isEmpty {
                        withAnimation {
                            viewModel.isSelectionMode = true
                            viewModel.selectedItems = Set(displayPictures)
                        }
                    }
                }
                .keyboardShortcut("a", modifiers: [.command])

                // Cmd+Delete (⌘⌫): Delete selected items
                Button("") {
                    if !viewModel.selectedItems.isEmpty && viewModel.manager.canManageCurrentFolder {
                        viewModel.itemsPendingDelete = Array(viewModel.selectedItems)
                    }
                }
                .keyboardShortcut(.delete, modifiers: [.command])

                // Cmd+M (⌘M): Move selected items to destination folder
                Button("") {
                    if !viewModel.selectedItems.isEmpty && viewModel.manager.canManageCurrentFolder {
                        viewModel.itemsPendingMove = Array(viewModel.selectedItems)
                    }
                }
                .keyboardShortcut("m", modifiers: [.command])
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
                await viewModel.manager.selectAndLoadFolder(folder)
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
    #if !os(tvOS)
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
    #endif
    
    /// Steps up the zoom level: if currently in List mode, switches to Compact Grid;
    /// if in Grid mode, cycles from Compact -> Medium -> Large with haptic feedback.
    private func zoomIn() {
        if viewMode == .list {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                viewMode = .grid
                gridSize = .compact
            }
            AppHapticFeedback.medium()
            return
        }
        
        switch gridSize {
        case .compact:
            $gridSize.animation(.spring(response: 0.38, dampingFraction: 0.8)).wrappedValue = .medium
            AppHapticFeedback.medium()
        case .medium:
            $gridSize.animation(.spring(response: 0.38, dampingFraction: 0.8)).wrappedValue = .large
            AppHapticFeedback.medium()
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
            AppHapticFeedback.medium()
        case .medium:
            $gridSize.animation(.spring(response: 0.38, dampingFraction: 0.8)).wrappedValue = .compact
            AppHapticFeedback.medium()
        case .compact:
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                viewMode = .list
            }
            AppHapticFeedback.medium()
        }
    }
    
    // MARK: - Batch Selection Actions
    
    /// Toggles the selection status of a single media item, triggering light haptic feedback.
    ///
    /// - Parameter item: The `MediaItem` to add to or remove from `viewModel.selectedItems`.
    private func toggleSelection(for item: MediaItem) {
        if viewModel.selectedItems.contains(item) {
            viewModel.selectedItems.remove(item)
        } else {
            viewModel.selectedItems.insert(item)
        }
        AppHapticFeedback.light()
    }
    
    /// Selects all visible media items if not already all selected; otherwise, clears the selection set.
    ///
    /// - Parameter pictures: The currently visible array of pictures subject to selection.
    private func toggleAllSelection(for pictures: [MediaItem]) {
        if viewModel.selectedItems.count == pictures.count && !pictures.isEmpty {
            viewModel.selectedItems.removeAll()
        } else {
            viewModel.selectedItems = Set(pictures)
        }
        AppHapticFeedback.medium()
    }
    
    /// Toggles the favorite status across all selected items.
    /// If all selected items are already marked as favorites, unmarks all of them; otherwise, marks any un-favorited items as favorite.
    private func batchToggleFavorites() {
        let items = Array(viewModel.selectedItems)
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
        AppHapticFeedback.medium()
    }
    
    /// Cancels any currently active batch save or batch share operation and resets progress flags.
    private func cancelBatchTask() {
        viewModel.batchTask?.cancel()
        viewModel.batchTask = nil
        viewModel.isBatchProcessing = false
        viewModel.batchProgressMessage = nil
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
        let items = Array(viewModel.selectedItems)
        guard !items.isEmpty else { return }
        viewModel.isBatchProcessing = true
        viewModel.batchTask?.cancel()
        
        viewModel.batchTask = Task { @MainActor in
            var completedCount = 0
            var savedCount = 0
            var failedCount = 0
            let total = items.count
            
            if total == 1, let item = items.first {
                viewModel.batchProgressMessage = String(localized: .Strings.galleryDownloadStartingItem(item.name))
                let throttler = DownloadProgressThrottler()
                let success = await Self.saveSingleMediaItemToPhotos(item, manager: viewModel.manager) { bytes, totalBytes in
                    Task {
                        guard await throttler.shouldReport(bytes: bytes, total: totalBytes) else { return }
                        await MainActor.run {
                            guard totalBytes > 0 else { return }
                            let readStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                            let totalStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                            let percent = (Double(bytes) / Double(totalBytes)).formatted(.percent.precision(.fractionLength(0)))
                            self.viewModel.batchProgressMessage = String(localized: .Strings.galleryDownloadProgressBytes(readStr, totalStr, percent))
                        }
                    }
                }
                completedCount = 1
                if success {
                    savedCount = 1
                } else {
                    failedCount = 1
                }
            } else {
                // Bounded concurrency pool (up to 3 parallel downloads to maximize network throughput without saturating memory)
                await withTaskGroup(of: Bool.self) { group in
                    var iterator = items.makeIterator()
                    let maxConcurrent = 3
                    
                    // Seed initial workers
                    for _ in 0..<min(maxConcurrent, total) {
                        if let nextItem = iterator.next() {
                            group.addTask { [manager = self.viewModel.manager] in
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
                        viewModel.batchProgressMessage = String(localized: .Strings.galleryBatchSavingToPhotos(completedCount, total))
                        
                        if let nextItem = iterator.next() {
                            group.addTask { [manager = self.viewModel.manager] in
                                await Self.saveSingleMediaItemToPhotos(nextItem, manager: manager)
                            }
                        }
                    }
                }
            }
            
            guard !Task.isCancelled else {
                viewModel.isBatchProcessing = false
                viewModel.batchProgressMessage = nil
                return
            }
            
            viewModel.isBatchProcessing = false
            viewModel.batchProgressMessage = nil
            
            withAnimation {
                if failedCount > 0 && savedCount > 0 {
                    viewModel.batchStatusToast = String(localized: .Strings.gallerySavedToPhotosPartial(savedCount, total))
                } else if failedCount > 0 && savedCount == 0 {
                    viewModel.batchStatusToast = String(localized: .Strings.gallerySavedToPhotosFailed)
                } else {
                    viewModel.batchStatusToast = savedCount == 1
                        ? String(localized: .Strings.gallerySavedToPhotosSingle)
                        : String(localized: .Strings.gallerySavedToPhotosMultiple(savedCount))
                }
                viewModel.isSelectionMode = false
                viewModel.selectedItems.removeAll()
            }
            
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation {
                viewModel.batchStatusToast = nil
            }
        }
    }
    
    // MARK: - Batch Download to Files
    
    /// Downloads selected media items directly to local files and presents the native document picker
    /// so the user can choose where to export or save them (e.g., iCloud Drive, Downloads, On My iPhone).
    private func batchDownloadToFiles() {
        let items = Array(viewModel.selectedItems)
        guard !items.isEmpty else { return }
        viewModel.isBatchProcessing = true
        viewModel.batchTask?.cancel()
        
        viewModel.batchTask = Task { @MainActor in
            var downloadedURLs: [URL] = []
            let total = items.count
            
            if total == 1, let item = items.first {
                viewModel.batchProgressMessage = String(localized: .Strings.galleryDownloadStartingItem(item.name))
                let throttler = DownloadProgressThrottler()
                do {
                    let url = try await viewModel.manager.downloadItemToFile(for: item) { bytes, totalBytes in
                        Task {
                            guard await throttler.shouldReport(bytes: bytes, total: totalBytes) else { return }
                            await MainActor.run {
                                guard totalBytes > 0 else { return }
                                let readStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                                let totalStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                                let percent = (Double(bytes) / Double(totalBytes)).formatted(.percent.precision(.fractionLength(0)))
                                self.viewModel.batchProgressMessage = String(localized: .Strings.galleryDownloadProgressBytes(readStr, totalStr, percent))
                            }
                        }
                    }
                    downloadedURLs.append(url)
                } catch {
                    loge("Failed to download \(item.name) to file: \(error.localizedDescription)")
                }
            } else {
                for (index, item) in items.enumerated() {
                    guard !Task.isCancelled else { break }
                    viewModel.batchProgressMessage = String(localized: .Strings.galleryDownloadBatchItemTitle(index + 1, total, item.name))
                    let throttler = DownloadProgressThrottler()
                    do {
                        let url = try await viewModel.manager.downloadItemToFile(for: item) { bytes, totalBytes in
                            Task {
                                guard await throttler.shouldReport(bytes: bytes, total: totalBytes) else { return }
                                await MainActor.run {
                                    guard totalBytes > 0 else { return }
                                    let readStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                                    let totalStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                                    let percent = (Double(bytes) / Double(totalBytes)).formatted(.percent.precision(.fractionLength(0)))
                                    self.viewModel.batchProgressMessage = String(localized: .Strings.galleryDownloadBatchItemDetail(index + 1, total, item.name, readStr, totalStr, percent))
                                }
                            }
                        }
                        downloadedURLs.append(url)
                    } catch {
                        loge("Failed to download \(item.name) to file: \(error.localizedDescription)")
                    }
                }
            }
            
            guard !Task.isCancelled else {
                viewModel.isBatchProcessing = false
                viewModel.batchProgressMessage = nil
                return
            }
            
            viewModel.isBatchProcessing = false
            viewModel.batchProgressMessage = nil
            
            if downloadedURLs.isEmpty {
                withAnimation {
                    viewModel.batchStatusToast = String(localized: .Strings.galleryBatchDownloadFailed)
                }
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation {
                    viewModel.batchStatusToast = nil
                }
            } else {
                #if !os(tvOS)
                viewModel.itemsPendingFileExport = downloadedURLs
                #else
                withAnimation {
                    viewModel.batchStatusToast = String(localized: .Strings.galleryBatchDownloadedCount(downloadedURLs.count))
                }
                #endif
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
    ///   - progress: Optional callback for reporting download progress.
    /// - Returns: `true` if the media item was successfully saved to Photos; otherwise, `false`.
    private static func saveSingleMediaItemToPhotos(
        _ item: MediaItem,
        manager: StorageLocationManager,
        progress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async -> Bool {
        do {
            if item.isVideo {
                let localURL = try await manager.fetchVideoURL(for: item, progress: progress)
                try await PhotoLibrarySaver.saveVideoToPhotos(at: localURL)
            } else {
                if let progress {
                    let localURL = try await manager.downloadItemToFile(for: item, progress: progress)
                    guard let image = UIImage(contentsOfFile: localURL.path) else {
                        return false
                    }
                    try await PhotoLibrarySaver.saveImageToPhotos(image)
                } else {
                    guard let image = await manager.downloadImage(for: item) else {
                        return false
                    }
                    try await PhotoLibrarySaver.saveImageToPhotos(image)
                }
            }
            return true
        } catch {
            loge("Failed to save \(item.name): \(error.localizedDescription)")
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
        let items = Array(viewModel.selectedItems)
        guard !items.isEmpty else { return }
        viewModel.isBatchProcessing = true
        viewModel.batchProgressMessage = String(localized: .Strings.galleryBatchPreparingShare)
        viewModel.batchTask?.cancel()
        
        viewModel.batchTask = Task { @MainActor in
            var shareables: [Any] = []
            let total = items.count
            var completedCount = 0
            
            // Use bounded concurrent workers to fetch and prepare shareables while preserving selection order
            await withTaskGroup(of: (Int, (any Sendable)?).self) { group in
                let itemQueue = Array(items.enumerated())
                var queueIndex = 0
                let maxConcurrent = 3
                
                for _ in 0..<min(maxConcurrent, total) where queueIndex < itemQueue.count {
                    let (idx, item) = itemQueue[queueIndex]
                    queueIndex += 1
                    group.addTask { [manager = self.viewModel.manager] in
                        let result = await Self.prepareSingleItemForShare(item, manager: manager)
                        return (idx, result)
                    }
                }
                
                var indexedResults: [(Int, any Sendable)] = []
                while let (idx, result) = await group.next() {
                    guard !Task.isCancelled else { break }
                    completedCount += 1
                    viewModel.batchProgressMessage = "\(String(localized: .Strings.galleryBatchPreparingShare)) (\(completedCount)/\(total))"
                    
                    if let result {
                        indexedResults.append((idx, result))
                    }
                    
                    if queueIndex < itemQueue.count {
                        let (nextIdx, nextItem) = itemQueue[queueIndex]
                        queueIndex += 1
                        group.addTask { [manager = self.viewModel.manager] in
                            let nextResult = await Self.prepareSingleItemForShare(nextItem, manager: manager)
                            return (nextIdx, nextResult)
                        }
                    }
                }
                
                indexedResults.sort { $0.0 < $1.0 }
                shareables = indexedResults.map { $0.1 as Any }
            }
            
            guard !Task.isCancelled else {
                viewModel.isBatchProcessing = false
                viewModel.batchProgressMessage = nil
                return
            }
            
            viewModel.isBatchProcessing = false
            viewModel.batchProgressMessage = nil
            
            if !shareables.isEmpty {
                self.viewModel.shareSheetItems = shareables
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
    private static func prepareSingleItemForShare(_ item: MediaItem, manager: StorageLocationManager) async -> (any Sendable)? {
        if item.isVideo {
            return try? await manager.fetchVideoURL(for: item)
        } else {
            return await manager.downloadImage(for: item)
        }
    }
    
    // MARK: - File Management Operations
    
    /// Indicates whether the currently pending delete batch targets items on an SMB network share.
    private var isDeletingFromSMB: Bool {
        viewModel.itemsPendingDelete?.contains(where: { $0.localURL == nil && !$0.shareName.isEmpty }) ?? false
    }
    
    /// Title presented inside the trash deletion confirmation dialog.
    private var deleteConfirmationTitle: String {
        guard let items = viewModel.itemsPendingDelete, !items.isEmpty else { return "" }
        if isDeletingFromSMB {
            if items.count == 1, let first = items.first {
                return String(localized: .Strings.galleryConfirmDeleteSinglePermanentTitle(first.name))
            }
            return String(localized: .Strings.galleryConfirmDeleteMultiplePermanentTitle(items.count))
        } else {
            if items.count == 1, let first = items.first {
                return String(localized: .Strings.galleryConfirmMoveSingleToTrashTitle(first.name))
            }
            return String(localized: .Strings.galleryConfirmMoveMultipleToTrashTitle(items.count))
        }
    }
    
    /// Button title for confirming deletion.
    private var deleteConfirmationButtonTitle: String {
        if isDeletingFromSMB {
            return String(localized: .Strings.galleryActionDeletePermanently)
        } else {
            return String(localized: .Strings.galleryActionMoveToTrash)
        }
    }
    
    /// Message explaining the permanent or trash nature of the pending delete.
    private var deleteConfirmationMessage: String {
        if isDeletingFromSMB {
            return String(localized: .Strings.galleryWarningPermanentDeleteSmb)
        } else {
            return String(localized: .Strings.galleryInfoMoveToTrash)
        }
    }
    
    /// Executes deletion across selected or targeted items.
    private func executeDelete(items: [MediaItem]) async {
        do {
            let wasSMB = items.contains(where: { $0.localURL == nil && !$0.shareName.isEmpty })
            try await viewModel.manager.deleteItems(items)
            if viewModel.isSelectionMode {
                withAnimation {
                    viewModel.isSelectionMode = false
                    viewModel.selectedItems.removeAll()
                }
            }
            if wasSMB {
                showToastMessage(items.count == 1 ? String(localized: .Strings.galleryToastSingleItemPermanentlyDeleted) : String(localized: .Strings.galleryToastMultipleItemsPermanentlyDeleted(items.count)))
            } else {
                showToastMessage(items.count == 1 ? String(localized: .Strings.galleryToastSingleItemMovedToTrash) : String(localized: .Strings.galleryToastMultipleItemsMovedToTrash(items.count)))
            }
        } catch {
            viewModel.fileOpErrorMessage = error.localizedDescription
        }
    }
    
    /// Dispatches moving items to the selected destination folder.
    private func executeMove(items: [MediaItem], to destination: MediaItem) {
        Task {
            do {
                try await viewModel.manager.moveItems(items, to: destination)
                if viewModel.isSelectionMode {
                    withAnimation {
                        viewModel.isSelectionMode = false
                        viewModel.selectedItems.removeAll()
                    }
                }
                let destName = destination.name.isEmpty ? destination.rootName : destination.name
                showToastMessage(items.count == 1 ? String(localized: .Strings.galleryToastSingleItemMoved(destName)) : String(localized: .Strings.galleryToastMultipleItemsMoved(items.count, destName)))
            } catch {
                viewModel.fileOpErrorMessage = error.localizedDescription
            }
        }
    }
    
    /// Creates a new directory inside the current folder.
    private func executeCreateFolder() {
        let trimmed = viewModel.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                try await viewModel.manager.createFolder(named: trimmed)
                showToastMessage(String(localized: .Strings.galleryToastFolderCreated(trimmed)))
            } catch {
                viewModel.fileOpErrorMessage = error.localizedDescription
            }
        }
    }
    
    /// Renames a file or folder and updates selection and toast notification.
    private func executeRename(item: MediaItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                let renamed = try await viewModel.manager.renameItem(item, to: trimmed)
                if viewModel.isSelectionMode {
                    withAnimation {
                        viewModel.selectedItems.remove(item)
                        viewModel.selectedItems.insert(renamed)
                    }
                }
                showToastMessage(
                    item.isDirectory
                        ? String(localized: .Strings.galleryToastFolderRenamed(renamed.name))
                        : String(localized: .Strings.galleryToastFileRenamed(renamed.name))
                )
            } catch {
                viewModel.fileOpErrorMessage = error.localizedDescription
            }
        }
    }
    
    /// Displays a transient animated notification pill at the top of the gallery.
    private func showToastMessage(_ message: String) {
        withAnimation {
            viewModel.batchStatusToast = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation {
                viewModel.batchStatusToast = nil
            }
        }
    }

    @ToolbarContentBuilder
    private func galleryToolbarContent(displayPictures: [MediaItem], hasImages: Bool) -> some ToolbarContent {
            if viewModel.isSelectionMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button(viewModel.selectedItems.count == displayPictures.count && !displayPictures.isEmpty ? .Strings.galleryButtonDeselectAll : .Strings.galleryButtonSelectAll) {
                        toggleAllSelection(for: displayPictures)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text(viewModel.selectedItems.isEmpty ? .Strings.gallerySelectionPrompt : .Strings.gallerySelectionCount(viewModel.selectedItems.count))
                        .font(.headline)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(.Strings.commonDone) {
                        withAnimation {
                            viewModel.isSelectionMode = false
                            viewModel.selectedItems.removeAll()
                        }
                    }
                    .font(.body.bold())
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Button {
                            if let parent = viewModel.manager.parentFolder {
                                navigateToFolder(parent)
                            }
                        } label: {
                            Image(systemName: "arrow.up.folder")
                                .fontWeight(.semibold)
                                .foregroundColor(viewModel.manager.parentFolder != nil ? .blue : .secondary.opacity(0.35))
                        }
                        .tint(.blue)
                        .disabled(viewModel.manager.parentFolder == nil)
                        .accessibilityLabel(parentFolderAccessibilityLabel)
                        
                        if viewModel.manager.canManageCurrentFolder {
                            Button {
                                viewModel.newFolderName = ""
                                viewModel.isShowingNewFolderAlert = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                            .tint(.blue)
                            .accessibilityLabel(Text(.Strings.commonNewFolder))
                        }
                        
                        if !displayPictures.isEmpty {
                            Button {
                                withAnimation {
                                    viewModel.isSelectionMode = true
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
                            
                            filterMenuSection
                            
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
                            
                            Section(String(localized: .Strings.gallerySectionDiskCache(viewModel.manager.mediaCacheSize))) {
                                Button(role: .destructive) {
                                    viewModel.manager.clearMediaCache()
                                } label: {
                                    Label(.Strings.galleryButtonClearCache, systemImage: "trash")
                                }
                            }
                            
                            #if DEBUG
                            Section("Debug") {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.manager.invalidateCurrentFolderThumbnails()
                                        viewModel.thumbnailReloadToken = UUID()
                                    }
                                } label: {
                                    Label("Invalidate Folder Thumbnails", systemImage: "arrow.triangle.2.circlepath.circle")
                                }
                            }
                            #endif
                            
                            if horizontalSizeClass == .compact {
                                Section {
                                    Button {
                                        viewModel.showingSettings = true
                                    } label: {
                                        Label(.Strings.settingsTitle, systemImage: "gearshape")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: (viewModel.mediaFilter != .all || viewModel.showFavoritesOnly) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                        
                        Button {
                            if let folder = viewModel.manager.selectedFolder {
                                Task { await viewModel.manager.selectAndLoadFolder(folder) }
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        
                        if horizontalSizeClass == .compact {
                            Button {
                                viewModel.showingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel(.Strings.settingsTitle)
                        }
                    }.padding(.horizontal)
                }
            }
    }
}
