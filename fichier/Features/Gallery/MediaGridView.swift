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
                                mediaSectionHeader: viewModel.mediaSectionHeader(for: displayPictures.count),
                                isSelectionMode: viewModel.isSelectionMode,
                                selectedItems: viewModel.selectedItems,
                                currentDirectoryID: viewModel.currentDirectoryID,
                                onNavigateToFolder: { navigateToFolder($0) },
                                onSelectPicture: {
                                    AppKeyboardDismissal.dismiss()
                                    onSelectPicture($0, $1)
                                },
                                onToggleSelection: { viewModel.toggleSelection(for: $0) },
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
                                mediaSectionHeader: viewModel.mediaSectionHeader(for: displayPictures.count),
                                isSelectionMode: viewModel.isSelectionMode,
                                selectedItems: viewModel.selectedItems,
                                currentDirectoryID: viewModel.currentDirectoryID,
                                onNavigateToFolder: { navigateToFolder($0) },
                                onSelectPicture: {
                                    AppKeyboardDismissal.dismiss()
                                    onSelectPicture($0, $1)
                                },
                                onToggleSelection: { viewModel.toggleSelection(for: $0) },
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
                    onCancel: { viewModel.cancelBatchTask() },
                    onToggleFavorite: { viewModel.batchToggleFavorites() },
                    onSaveToPhotos: { viewModel.batchSaveToPhotos() },
                    onDownloadToFiles: { viewModel.batchDownloadToFiles() },
                    onShare: { viewModel.batchShare() },
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
                            viewModel.isSelectionMode = false
                            viewModel.selectedItems.removeAll()
                        }
                        viewModel.showToastMessage(String(localized: .Strings.galleryBatchSavedToFiles(urls.count)))
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
                        viewModel.executeMove(items: items, to: destination)
                    },
                    onDismiss: {
                        viewModel.itemsPendingMove = nil
                    }
                )
            }
        }
        .confirmationDialog(
            viewModel.deleteConfirmationTitle,
            isPresented: Binding(
                get: { viewModel.itemsPendingDelete != nil },
                set: { if !$0 { viewModel.itemsPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(viewModel.deleteConfirmationButtonTitle, role: .destructive) {
                if let items = viewModel.itemsPendingDelete {
                    viewModel.itemsPendingDelete = nil
                    Task {
                        await viewModel.executeDelete(items: items)
                    }
                }
            }
            Button(.Strings.commonCancel, role: .cancel) {
                viewModel.itemsPendingDelete = nil
            }
        } message: {
            Text(verbatim: viewModel.deleteConfirmationMessage)
        }
        .alert(
            .Strings.commonNewFolder,
            isPresented: $viewModel.isShowingNewFolderAlert
        ) {
            TextField(String(localized: .Strings.commonFolderName), text: $viewModel.newFolderName)
            Button(.Strings.commonCancel, role: .cancel) {}
            Button(.Strings.commonCreate) {
                viewModel.executeCreateFolder()
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
                    viewModel.executeRename(item: item, to: viewModel.renameText)
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
                            viewModel.cancelBatchTask()
                        }
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                // Cmd+A: Select All / Deselect All (when in selection mode)
                Button("") {
                    if viewModel.isSelectionMode {
                        viewModel.toggleAllSelection(for: displayPictures)
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

    @ToolbarContentBuilder
    private func galleryToolbarContent(displayPictures: [MediaItem], hasImages: Bool) -> some ToolbarContent {
            if viewModel.isSelectionMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button(viewModel.selectedItems.count == displayPictures.count && !displayPictures.isEmpty ? .Strings.galleryButtonDeselectAll : .Strings.galleryButtonSelectAll) {
                        viewModel.toggleAllSelection(for: displayPictures)
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
                                SlideshowDurationPickerView(selection: $slideshowInterval)
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
                                
                                SlideshowDurationPickerView(selection: $slideshowInterval)
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
                    }.padding(.horizontal)
                }
            }
    }
}
