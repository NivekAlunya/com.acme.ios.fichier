//
//  FolderTreeContentView.swift
//  fichier
//

import FichierKit
import SwiftUI

/// Intermediate content column in the `NavigationSplitView` displaying the active location's directory hierarchy.
///
/// Handles three distinct visual states:
/// 1. **Disconnected**: Renders a `ContentUnavailableView` inviting the user to configure or select a remote location.
/// 2. **Connecting / Empty**: Renders an indeterminate progress view or an empty shares notification with refresh actions.
/// 3. **Connected with Shares**: Embeds `SidebarFolderTreeView` to present the hierarchical folder tree.
public struct FolderTreeContentView: View {
    /// Two-way bindable reference to the centralized storage location manager.
    @Bindable var manager: StorageLocationManager
    
    /// Binding controlling presentation of the new SMB connection sheet.
    @Binding var showingAddRemote: Bool
    
    /// Optional callback to reveal or navigate back to the sidebar programmatically.
    var onOpenSidebar: (() -> Void)? = nil

    /// Callback invoked when a folder item is selected in the tree.
    let onSelectFolder: (MediaItem) -> Void
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - manager: Shared storage location manager.
    ///   - showingAddRemote: Binding for connection sheet presentation.
    ///   - onOpenSidebar: Optional callback to reveal the sidebar.
    ///   - onSelectFolder: Callback receiving the selected folder item.
    public init(
        manager: StorageLocationManager,
        showingAddRemote: Binding<Bool>,
        onOpenSidebar: (() -> Void)? = nil,
        onSelectFolder: @escaping (MediaItem) -> Void
    ) {
        self.manager = manager
        self._showingAddRemote = showingAddRemote
        self.onOpenSidebar = onOpenSidebar
        self.onSelectFolder = onSelectFolder
    }
    
    public var body: some View {
        Group {
            if manager.hasSelectedDrive {
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
                        onOpenSidebar: onOpenSidebar,
                        onSelectFolder: onSelectFolder
                    )
                }
            } else if manager.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(.Strings.sidebarLoadingShares)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if manager.isConnected && manager.currentLocation?.kind == .smb {
                ContentUnavailableView {
                    Label(
                        String(localized: .Strings.folders),
                        systemImage: "folder"
                    )
                } description: {
                    Text(.Strings.selectStorageDescription)
                } actions: {
                    if let onOpenSidebar {
                        Button {
                            onOpenSidebar()
                        } label: {
                            Label(
                                String(localized: .Strings.selectStorage),
                                systemImage: "sidebar.leading"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else if !manager.allLocations.isEmpty {
                ContentUnavailableView {
                    Label(
                        String(localized: .Strings.folders),
                        systemImage: "folder"
                    )
                } description: {
                    Text(.Strings.selectStorageDescription)
                } actions: {
                    if let onOpenSidebar {
                        Button {
                            onOpenSidebar()
                        } label: {
                            Label(
                                String(localized: .Strings.selectStorage),
                                systemImage: "sidebar.leading"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label(
                        String(localized: .Strings.folders),
                        systemImage: "folder"
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
                    
                    if let onOpenSidebar {
                        Button {
                            onOpenSidebar()
                        } label: {
                            Label(
                                String(localized: .Strings.selectStorage),
                                systemImage: "sidebar.leading"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .onChange(of: manager.navigationCoordinator.mutationRevision) { _, _ in
            if manager.hasSelectedDrive && manager.folderTree.isEmpty {
                Task {
                    await manager.refreshSharesAndFolders()
                }
            }
        }
    }
    
    /// Computes the column title reflecting the current connection name or active folder.
    private var navigationTitle: String {
        guard manager.hasSelectedDrive else {
            return String(localized: .Strings.folders)
        }
        
        let shareDrive: String = {
            if manager.currentLocation?.kind == .smb {
                return manager.selectedShare?.name ?? manager.currentLocation?.name ?? ""
            }
            if let location = manager.currentLocation {
                return location.name
            }
            if let remote = manager.savedConnections.first(where: { manager.currentConnectionID == $0.id }) {
                return remote.displayName
            }
            return ""
        }()
        
        guard !shareDrive.isEmpty else {
            return String(localized: .Strings.folders)
        }
        
        if let folder = manager.selectedFolder {
            let isRoot = folder.path.isEmpty || folder.path == "/" || folder.name == shareDrive || folder.name == "/"
            if !isRoot {
                return "\(shareDrive) / \(folder.name)"
            }
        }
        return shareDrive
    }
}
