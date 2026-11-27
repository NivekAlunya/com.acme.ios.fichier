//
//  MediaBrowserSplitView.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Root visual container for the application, organizing navigation into a two-column `NavigationSplitView`.
///
/// ### Architecture & Navigation Hierarchy
/// - **Column 1 (Sidebar)**: `LocationsSidebarView` displays available storage roots (Photos, Local, iCloud, SMB)
///   alongside the hierarchical folder tree (`SidebarFolderTreeView`) for the active drive or share.
/// - **Column 2 (Detail)**: `MediaGridView` renders thumbnail collections, folder contents, and action toolbars.
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

    /// Shared namespace coordinating zoom-from-thumbnail full-screen viewer transitions.
    @Namespace private var viewerTransitionNamespace
    
    /// Default public initializer.
    public init() {}
    
    public var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            // 1. Sidebar: Unified Locations list + active drive's folder tree
            LocationsSidebarView(
                manager: storageManager,
                showingAddRemote: $showingAddRemote,
                showingSettings: $showingSettings,
                connectingLocationID: connectingLocationID,
                onSelectLocation: { location in
                    selectLocation(location)
                },
                onSelectShare: { share in
                    selectShare(share)
                },
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
                        viewerTransitionNamespace: viewerTransitionNamespace,
                        onSelectFolder: { subfolder in
                            Task {
                                await storageManager.selectAndLoadFolder(subfolder)
                                preferredCompactColumn = .detail
                            }
                        },
                        onStartSlideshow: { currentDisplayPictures in
                            AppKeyboardDismissal.dismiss()
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
                            AppKeyboardDismissal.dismiss()
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
                        VStack(spacing: 8) {
                            Text(.Strings.galleryNoFolderSelectedDescription)
                            HStack(spacing: 5) {
                                Image(systemName: "sidebar.leading")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tint)
                                Text(.Strings.selectStorageSidebarInstruction)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle(storageManager.selectedFolder?.name ?? String(localized: .Strings.connectionTitleFiles))
                }
            }
            .fichierAtmosphericBackground()
        }
        .fullScreenCover(item: $activePictureContext) { context in
            PictureDetailView(
                manager: storageManager,
                pictures: context.resolvedItems(matching: \.isImage),
                initialItem: context.item,
                autoStartSlideshow: shouldAutoStartSlideshow
            )
            .navigationTransition(.zoom(sourceID: context.item.id, in: viewerTransitionNamespace))
        }
        .fullScreenCover(item: $activeVideoContext) { context in
            VideoDetailView(
                manager: storageManager,
                videos: context.resolvedItems(matching: \.isVideo),
                initialItem: context.item
            )
        }
        #if !os(tvOS)
        .fullScreenCover(item: $activePDFContext) { context in
            PDFDetailView(
                manager: storageManager,
                documents: context.resolvedItems(matching: \.isPDF),
                initialItem: context.item
            )
            .navigationTransition(.zoom(sourceID: context.item.id, in: viewerTransitionNamespace))
        }
        #endif
        .sheet(isPresented: $showingSettings) {
            AppSettingsView(manager: storageManager)
        }
        .sheet(isPresented: $showingAddRemote) {
            SMBConnectWithDiscoveryView(smbManager: storageManager)
        }
        .onDisappear {
            connectionTask?.cancel()
            connectionTask = nil
            connectingLocationID = nil
        }
    }
    
    /// Asynchronously activates a storage location with haptic feedback and cooperative task cancellation.
    ///
    /// - Parameter location: The target location selected by the user.
    private func selectLocation(_ location: StorageLocation) {
        if storageManager.isConnected && storageManager.currentLocation?.id == location.id {
            if location.kind == .smb {
                preferredCompactColumn = .sidebar
            } else {
                preferredCompactColumn = storageManager.selectedFolder != nil ? .detail : .sidebar
            }
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
                if location.kind == .smb {
                    // Keep sidebar focused so the expanded shares list is immediately visible
                    preferredCompactColumn = .sidebar
                } else {
                    preferredCompactColumn = storageManager.selectedFolder != nil ? .detail : .sidebar
                }
            }
        }
    }
    
    /// Selects an SMB share as the active browsing source with haptic feedback.
    ///
    /// - Parameter share: The target SMB share selected from the sidebar.
    private func selectShare(_ share: MediaItem) {
        AppHapticFeedback.light()
        Task {
            await storageManager.selectShare(share)
            preferredCompactColumn = .detail
        }
    }
}
