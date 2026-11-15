//
//  MediaBrowserSplitView.swift
//  fichier
//

import SwiftUI

/// Root visual container for the application, organizing navigation into a three-column `NavigationSplitView`.
///
/// ### Architecture & Navigation Hierarchy
/// - **Column 1 (Sidebar)**: `LocationsSidebarView` displays available storage roots (Photos, Local, iCloud, SMB).
/// - **Column 2 (Content)**: `FolderTreeContentView` presents the hierarchical folder tree for the connected location.
/// - **Column 3 (Detail)**: `MediaGridView` renders thumbnail collections, folder contents, and action toolbars.
///
/// Also acts as the coordinator presenting full-screen viewers:
/// - `PictureDetailView` for full-resolution photo inspection and automated slideshows.
/// - `VideoDetailView` for custom AVPlayer video playback and audio/subtitle track selection.
/// - `PDFDetailView` for document rendering via PDFKit.
public struct MediaBrowserSplitView: View {
    /// Centralized storage location manager driving application state.
    @State private var storageManager = StorageLocationManager()
    
    /// Target photo presentation context containing the focused item and the active filtered/sorted gallery items.
    @State private var activePictureContext: MediaViewerContext?
    
    /// Target video presentation context containing the focused item and the active filtered/sorted playlist items.
    @State private var activeVideoContext: MediaViewerContext?
    
    #if !os(tvOS)
    /// Target PDF presentation context containing the focused item and the active filtered/sorted document items.
    @State private var activePDFContext: MediaViewerContext?
    #endif
    
    /// Flag signaling `PictureDetailView` to commence automatic slideshow cycling immediately on appearance.
    @State private var shouldAutoStartSlideshow = false
    
    /// Split view column visibility control (defaults to showing all columns on iPad / Mac).
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    /// Column focus preference for compact iPhone size classes.
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    /// Controls presentation of the application settings sheet.
    @State private var showingSettings = false
    
    /// Controls presentation of the SMB server connection and discovery sheet.
    @State private var showingAddRemote = false
    
    /// Tracks which location ID is currently in the process of connecting to show spinners.
    @State private var connectingLocationID: String?
    
    /// Cancellable background task handling asynchronous location selection.
    @State private var connectionTask: Task<Void, Never>?
    
    /// Default public initializer.
    public init() {}
    
    public var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            // 1. Sidebar: Unified Locations list (iCloud, Local, SMB)
            LocationsSidebarView(
                manager: storageManager,
                showingAddRemote: $showingAddRemote,
                showingSettings: $showingSettings,
                connectingLocationID: connectingLocationID,
                onSelectLocation: { location in
                    selectLocation(location)
                }
            )
        } content: {
            // 2. Content: Folder Tree of the selected/connected remote
            FolderTreeContentView(
                manager: storageManager,
                showingAddRemote: $showingAddRemote,
                onSelectFolder: { folder in
                    Task {
                        await storageManager.selectAndLoadFolder(folder)
                        preferredCompactColumn = .detail
                    }
                }
            )
        } detail: {
            // 3. Detail: Media Grid and navigation toolbar
            Group {
                if let selectedFolder = storageManager.selectedFolder {
                    MediaGridView(
                        manager: storageManager,
                        onSelectFolder: { subfolder in
                            Task {
                                await storageManager.selectAndLoadFolder(subfolder)
                                preferredCompactColumn = .detail
                            }
                        },
                        onStartSlideshow: { currentDisplayPictures in
                            let photosOnly = currentDisplayPictures.filter(\.isImage)
                            if let first = photosOnly.first {
                                activePictureContext = MediaViewerContext(
                                    item: first,
                                    contextItems: currentDisplayPictures
                                )
                                shouldAutoStartSlideshow = true
                            }
                        },
                        onSelectPicture: { item, currentDisplayPictures in
                            let context = MediaViewerContext(
                                item: item,
                                contextItems: currentDisplayPictures
                            )
                            #if !os(tvOS)
                            if item.isPDF {
                                activePDFContext = context
                            } else if item.isVideo {
                                activeVideoContext = context
                            } else {
                                activePictureContext = context
                                shouldAutoStartSlideshow = false
                            }
                            #else
                            if item.isVideo {
                                activeVideoContext = context
                            } else {
                                activePictureContext = context
                                shouldAutoStartSlideshow = false
                            }
                            #endif
                        }
                    )
                    .navigationTitle(selectedFolder.name)
                } else {
                    ContentUnavailableView {
                        Label(
                            String(localized: .Strings.galleryNoFolderSelectedTitle),
                            systemImage: "photo.on.rectangle.angled"
                        )
                    } description: {
                        Text(.Strings.galleryNoFolderSelectedDescription)
                    }
                    .navigationTitle(storageManager.selectedFolder?.name ?? String(localized: .Strings.connectionTitleFiles))
                }
            }
        }
        .fullScreenCover(item: $activePictureContext) { context in
            let activeImages = context.contextItems.filter(\.isImage)
            var gallery = activeImages.isEmpty ? [context.item] : activeImages
            if !gallery.contains(where: { $0.id == context.item.id }) {
                gallery.append(context.item)
            }
            return PictureDetailView(
                manager: storageManager,
                pictures: gallery,
                initialItem: context.item,
                autoStartSlideshow: shouldAutoStartSlideshow
            )
        }
        .fullScreenCover(item: $activeVideoContext) { context in
            let activeVideos = context.contextItems.filter(\.isVideo)
            var playlist = activeVideos.isEmpty ? [context.item] : activeVideos
            if !playlist.contains(where: { $0.id == context.item.id }) {
                playlist.append(context.item)
            }
            return VideoDetailView(
                manager: storageManager,
                videos: playlist,
                initialItem: context.item
            )
        }
        #if !os(tvOS)
        .fullScreenCover(item: $activePDFContext) { context in
            let activeDocuments = context.contextItems.filter(\.isPDF)
            var documents = activeDocuments.isEmpty ? [context.item] : activeDocuments
            if !documents.contains(where: { $0.id == context.item.id }) {
                documents.append(context.item)
            }
            return PDFDetailView(
                manager: storageManager,
                documents: documents,
                initialItem: context.item
            )
        }
        #endif
        .sheet(isPresented: $showingSettings) {
            AppSettingsView()
        }
        .sheet(isPresented: $showingAddRemote) {
            SMBConnectWithDiscoveryView(smbManager: storageManager)
        }
    }
    
    /// Asynchronously activates a storage location with haptic feedback and cooperative task cancellation.
    ///
    /// - Parameter location: The target location selected by the user.
    private func selectLocation(_ location: StorageLocation) {
        if storageManager.isConnected && storageManager.currentLocation?.id == location.id {
            preferredCompactColumn = .content
            return
        }
        
        connectionTask?.cancel()
        connectingLocationID = location.id
        AppHapticFeedback.light()
        
        connectionTask = Task {
            await storageManager.selectLocation(location)
            guard !Task.isCancelled else { return }
            connectingLocationID = nil
            if storageManager.isConnected {
                // If a folder was automatically restored or loaded, navigate directly to detail on compact layouts
                preferredCompactColumn = storageManager.selectedFolder != nil ? .detail : .content
            }
        }
    }
}
