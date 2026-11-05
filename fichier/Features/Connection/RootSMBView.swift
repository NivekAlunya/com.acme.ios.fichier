//
//  RootSMBView.swift
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
public struct RootSMBView: View {
    /// Centralized storage location manager driving application state.
    @State private var smbManager = StorageLocationManager()
    
    /// Target image media item for presenting the full-screen photo viewer.
    @State private var activePictureForViewer: MediaItem?
    
    /// Target video media item for presenting the full-screen video player.
    @State private var activeVideoForViewer: MediaItem?
    
    /// Target PDF media item for presenting the full-screen document viewer.
    @State private var activePDFForViewer: MediaItem?
    
    /// Filtered or sorted snapshot of media items from the active gallery, passed as paging context.
    @State private var activeContextMedia: [MediaItem] = []
    
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
                manager: smbManager,
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
                manager: smbManager,
                showingAddRemote: $showingAddRemote,
                onSelectFolder: { folder in
                    Task {
                        await smbManager.selectAndLoadFolder(folder)
                        preferredCompactColumn = .detail
                    }
                }
            )
        } detail: {
            // 3. Detail: Media Grid & Viewer
            Group {
                if let selectedFolder = smbManager.selectedFolder {
                    MediaGridView(
                        manager: smbManager,
                        onSelectFolder: { subfolder in
                            Task {
                                await smbManager.selectAndLoadFolder(subfolder)
                                preferredCompactColumn = .detail
                            }
                        },
                        onStartSlideshow: { currentDisplayPictures in
                            let photosOnly = currentDisplayPictures.filter(\.isImage)
                            if let first = photosOnly.first {
                                activeContextMedia = currentDisplayPictures
                                activePictureForViewer = first
                                shouldAutoStartSlideshow = true
                            }
                        },
                        onSelectPicture: { item, currentDisplayPictures in
                            activeContextMedia = currentDisplayPictures
                            if item.isPDF {
                                activePDFForViewer = item
                            } else if item.isVideo {
                                activeVideoForViewer = item
                            } else {
                                activePictureForViewer = item
                                shouldAutoStartSlideshow = false
                            }
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
                    .navigationTitle(smbManager.selectedFolder?.name ?? String(localized: .Strings.connectionTitleFiles))
                }
            }
        }
        .fullScreenCover(item: $activePictureForViewer) { pic in
            let context = activeContextMedia.isEmpty ? smbManager.pictures : activeContextMedia
            PictureDetailView(
                manager: smbManager,
                pictures: context.filter { !$0.isVideo && !$0.isPDF },
                initialItem: pic,
                autoStartSlideshow: shouldAutoStartSlideshow
            )
        }
        .fullScreenCover(item: $activeVideoForViewer) { vid in
            let source = activeContextMedia.contains(where: \.isVideo) ? activeContextMedia : smbManager.pictures
            var playlist = source.filter(\.isVideo)
            if !playlist.contains(where: { $0.id == vid.id }) {
                playlist.append(vid)
            }
            return VideoDetailView(
                manager: smbManager,
                videos: playlist.isEmpty ? [vid] : playlist,
                initialItem: vid
            )
        }
        .fullScreenCover(item: $activePDFForViewer) { pdf in
            PDFDetailView(
                manager: smbManager,
                item: pdf
            )
        }
        .sheet(isPresented: $showingSettings) {
            AppSettingsView()
        }
        .sheet(isPresented: $showingAddRemote) {
            SMBConnectWithDiscoveryView(smbManager: smbManager)
        }
    }
    
    /// Asynchronously activates a storage location with haptic feedback and cooperative task cancellation.
    ///
    /// - Parameter location: The target location selected by the user.
    private func selectLocation(_ location: StorageLocation) {
        if smbManager.isConnected && smbManager.currentLocation?.id == location.id {
            preferredCompactColumn = .content
            return
        }
        
        connectionTask?.cancel()
        connectingLocationID = location.id
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        connectionTask = Task {
            await smbManager.selectLocation(location)
            guard !Task.isCancelled else { return }
            connectingLocationID = nil
            if smbManager.isConnected {
                // If a folder was automatically restored or loaded, navigate directly to detail on compact layouts
                preferredCompactColumn = smbManager.selectedFolder != nil ? .detail : .content
            }
        }
    }
}
