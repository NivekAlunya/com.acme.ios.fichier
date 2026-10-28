//
//  RootSMBView.swift
//  fichier
//

import SwiftUI

public struct RootSMBView: View {
    @State private var smbManager = SMBDirectManager()
    @State private var activePictureForViewer: SMBItem?
    @State private var activeVideoForViewer: SMBItem?
    @State private var shouldAutoStartSlideshow = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    public init() {}
    
    public var body: some View {
        Group {
            if !smbManager.isConnected {
                // 1. Not connected -> Show Bonjour Discovery & Login Form
                SMBConnectWithDiscoveryView(smbManager: smbManager)
            } else {
                // 2. Connected -> SplitView with Shared Folders Tree Sidebar & Media Grid View
                NavigationSplitView(
                    columnVisibility: $columnVisibility,
                    preferredCompactColumn: $preferredCompactColumn
                ) {
                    SidebarFolderTreeView(
                        manager: smbManager,
                        onSelectFolder: { folder in
                            Task {
                                await smbManager.selectAndLoadFolder(folder)
                                preferredCompactColumn = .detail
                            }
                        }
                    )
                    .navigationTitle("Shared Folders")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Disconnect", role: .destructive) {
                                smbManager.disconnect()
                            }
                        }
                    }
                } detail: {
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
                    .navigationTitle(smbManager.selectedFolder?.name ?? "Files")
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
            }
        }
    }
}
