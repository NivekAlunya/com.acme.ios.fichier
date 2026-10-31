//
//  RootSMBView.swift
//  fichier
//

import SwiftUI

public struct RootSMBView: View {
    @State private var smbManager = SMBDirectManager()
    @State private var activePictureForViewer: MediaItem?
    @State private var activeVideoForViewer: MediaItem?
    @State private var shouldAutoStartSlideshow = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var showingSettings = false
    @State private var showingAddRemote = false
    @State private var connectingLocationID: String?
    @State private var connectionTask: Task<Void, Never>?
    
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
                        onStartSlideshow: {
                            let photosOnly = smbManager.pictures.filter { !$0.isVideo }
                            if let first = photosOnly.first {
                                activePictureForViewer = first
                                shouldAutoStartSlideshow = true
                            }
                        },
                        onSelectPicture: { item in
                            if item.isVideo {
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
            PictureDetailView(
                manager: smbManager,
                pictures: smbManager.pictures.filter { !$0.isVideo },
                initialItem: pic,
                autoStartSlideshow: shouldAutoStartSlideshow
            )
        }
        .fullScreenCover(item: $activeVideoForViewer) { vid in
            VideoDetailView(
                manager: smbManager,
                videos: smbManager.pictures.filter { $0.isVideo },
                initialItem: vid
            )
        }
        .sheet(isPresented: $showingSettings) {
            AppSettingsView()
        }
        .sheet(isPresented: $showingAddRemote) {
            SMBConnectWithDiscoveryView(smbManager: smbManager)
        }
    }
    
    private func selectLocation(_ location: StorageLocation) {
        if smbManager.isConnected && smbManager.currentConnectionID == location.id {
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
                preferredCompactColumn = .content
            }
        }
    }
}
