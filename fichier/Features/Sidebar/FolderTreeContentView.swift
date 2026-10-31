//
//  FolderTreeContentView.swift
//  fichier
//

import SwiftUI

public struct FolderTreeContentView: View {
    @Bindable var manager: SMBDirectManager
    @Binding var showingAddRemote: Bool
    let onSelectFolder: (SMBItem) -> Void
    
    public init(
        manager: SMBDirectManager,
        showingAddRemote: Binding<Bool>,
        onSelectFolder: @escaping (SMBItem) -> Void
    ) {
        self.manager = manager
        self._showingAddRemote = showingAddRemote
        self.onSelectFolder = onSelectFolder
    }
    
    public var body: some View {
        Group {
            if manager.isConnected {
                if manager.folderTree.isEmpty {
                    if manager.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(.Strings.sidebarLoadingShares)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ContentUnavailableView {
                            Label(
                                String(localized: .Strings.networkingErrorNoSharedFolders),
                                systemImage: "folder.badge.questionmark"
                            )
                        } description: {
                            Text(.Strings.sidebarNoSharesDescription)
                        } actions: {
                            Button {
                                Task {
                                    await manager.refreshSharesAndFolders()
                                }
                            } label: {
                                Text(.Strings.connectionButtonRefresh)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    SidebarFolderTreeView(
                        manager: manager,
                        onSelectFolder: onSelectFolder
                    )
                }
            } else {
                ContentUnavailableView {
                    Label(
                        String(localized: .Strings.sidebarNoConnectedRemoteTitle),
                        systemImage: "externaldrive.badge.xmark"
                    )
                } description: {
                    Text(.Strings.sidebarNoConnectedRemoteDescription)
                } actions: {
                    Button {
                        showingAddRemote = true
                    } label: {
                        Text(.Strings.sidebarButtonAddRemote)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(navigationTitle)
    }
    
    private var navigationTitle: String {
        if let location = manager.currentLocation {
            return location.name
        }
        if let remote = manager.savedConnections.first(where: { manager.currentConnectionID == $0.id }) {
            return remote.displayName
        }
        return String(localized: .Strings.connectionTitleSharedFolders)
    }
}
