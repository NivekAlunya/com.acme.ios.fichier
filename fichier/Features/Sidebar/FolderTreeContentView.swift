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
    
    /// Callback invoked when a folder item is selected in the tree.
    let onSelectFolder: (MediaItem) -> Void
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - manager: Shared storage location manager.
    ///   - showingAddRemote: Binding for connection sheet presentation.
    ///   - onSelectFolder: Callback receiving the selected folder item.
    public init(
        manager: StorageLocationManager,
        showingAddRemote: Binding<Bool>,
        onSelectFolder: @escaping (MediaItem) -> Void
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
    
    /// Computes the column title reflecting the current connection name or active folder.
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
