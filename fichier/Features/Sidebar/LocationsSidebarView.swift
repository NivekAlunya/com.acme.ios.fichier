//
//  LocationsSidebarView.swift
//  fichier
//

import SwiftUI
import UniformTypeIdentifiers

/// Primary sidebar view displaying the list of all configured and discovered storage locations.
///
/// Presents available storage providers:
/// - System Apple Photos library (permanent, cannot be deleted).
/// - Local on-device sandboxed directories added via `fileImporter`.
/// - iCloud Drive ubiquitous document folders added via `fileImporter`.
/// - Authenticated SMB file servers.
///
/// Features include folder import via security-scoped bookmarks, swipe-to-delete removal,
/// connection progress spinners, and quick access to application settings.
public struct LocationsSidebarView: View {
    /// Two-way bindable reference to the centralized storage location manager.
    @Bindable var manager: StorageLocationManager
    
    /// Binding controlling presentation of the new SMB connection sheet.
    @Binding var showingAddRemote: Bool
    
    /// Binding controlling presentation of the application settings sheet.
    @Binding var showingSettings: Bool
    
    /// Identifier of the storage location currently attempting connection, displaying an inline spinner.
    let connectingLocationID: String?
    
    /// Callback triggered when the user taps a storage location row.
    let onSelectLocation: (StorageLocation) -> Void
    
    /// Controls presentation of the system directory document picker (`.fileImporter`).
    @State private var showingFolderPicker = false
    
    /// Error message captured during document picker security bookmark creation.
    @State private var folderPickerErrorMessage: String?
    
    /// Controls presentation of error alerts originating from directory import failures.
    @State private var showingFolderErrorAlert = false
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - manager: Shared storage location manager.
    ///   - showingAddRemote: Binding for connection sheet.
    ///   - showingSettings: Binding for settings sheet.
    ///   - connectingLocationID: Active connecting location ID.
    ///   - onSelectLocation: Location selection handler.
    public init(
        manager: StorageLocationManager,
        showingAddRemote: Binding<Bool>,
        showingSettings: Binding<Bool>,
        connectingLocationID: String?,
        onSelectLocation: @escaping (StorageLocation) -> Void
    ) {
        self.manager = manager
        self._showingAddRemote = showingAddRemote
        self._showingSettings = showingSettings
        self.connectingLocationID = connectingLocationID
        self.onSelectLocation = onSelectLocation
    }
    
    public var body: some View {
        List {
            Section {
                if manager.allLocations.isEmpty {
                    ContentUnavailableView {
                        Label(
                            String(localized: .Strings.sidebarNoSavedLocationsTitle),
                            systemImage: "externaldrive.badge.plus"
                        )
                    } description: {
                        Text(.Strings.sidebarNoSavedLocationsDescription)
                    } actions: {
                        Menu {
                            addLocationMenuContent
                        } label: {
                            Text(.Strings.sidebarMenuAddLocation)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ForEach(manager.allLocations) { location in
                        HStack(spacing: 12) {
                            Button {
                                onSelectLocation(location)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: location.systemIcon)
                                        .foregroundColor(location.iconColor)
                                        .font(.title3)
                                        .frame(width: 28)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(location.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        
                                        if let subtitle = location.subtitle {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            if isConnecting(location) {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if isCurrentLocation(location) {
                                if location.kind == .smb {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 8, height: 8)
                                        
                                        Button {
                                            Task {
                                                await manager.disconnect()
                                            }
                                        } label: {
                                            Image(systemName: "eject.fill")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel(.Strings.connectionButtonDisconnect)
                                    }
                                } else {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                        .deleteDisabled(location.kind == .photos)
                        .contextMenu {
                            if isCurrentLocation(location) && location.kind == .smb {
                                Button(role: .destructive) {
                                    Task {
                                        await manager.disconnect()
                                    }
                                } label: {
                                    Label(.Strings.connectionButtonDisconnect, systemImage: "eject")
                                }
                            }
                            if location.kind != .photos {
                                Button(role: .destructive) {
                                    Task {
                                        await manager.removeLocation(location)
                                    }
                                } label: {
                                    Label(String(localized: "Remove Location"), systemImage: "trash")
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        let locationsToRemove = indexSet.map { manager.allLocations[$0] }
                        for loc in locationsToRemove where loc.kind != .photos {
                            Task {
                                await manager.removeLocation(loc)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text(.Strings.sidebarSectionLocations)
                    Spacer()
                    Menu {
                        addLocationMenuContent
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(.Strings.sidebarMenuAddLocation)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(.Strings.sidebarTitleBrowse)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(.Strings.settingsTitle)
            }
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let saved = try LocalStorageActor.createSavedFolderLocation(from: url)
                    manager.addSavedFolderLocation(saved)
                    let loc = StorageLocation(folder: saved)
                    onSelectLocation(loc)
                } catch {
                    folderPickerErrorMessage = error.localizedDescription
                    showingFolderErrorAlert = true
                }
            case .failure(let error):
                folderPickerErrorMessage = error.localizedDescription
                showingFolderErrorAlert = true
            }
        }
        .alert(
            Text(.Strings.galleryErrorUnableToLoadFolder),
            isPresented: $showingFolderErrorAlert,
            actions: {
                Button(.Strings.commonCancel, role: .cancel) {}
            },
            message: {
                Text(folderPickerErrorMessage ?? "")
            }
        )
    }
    
    /// Content for the '+' location menu presenting options for local, cloud, and network locations.
    @ViewBuilder
    private var addLocationMenuContent: some View {
        Button {
            showingFolderPicker = true
        } label: {
            Label(.Strings.sidebarMenuAddIcloudFolder, systemImage: "icloud")
        }
        
        Button {
            showingFolderPicker = true
        } label: {
            Label(.Strings.sidebarMenuAddLocalFolder, systemImage: "iphone")
        }
        
        Divider()
        
        Button {
            showingAddRemote = true
        } label: {
            Label(.Strings.sidebarMenuConnectSmb, systemImage: "macmini")
        }
    }
    
    /// Tests whether the given location is currently active and connected.
    private func isCurrentLocation(_ location: StorageLocation) -> Bool {
        manager.isConnected && manager.currentLocation?.id == location.id
    }
    
    /// Tests whether the given location is currently establishing an asynchronous connection.
    private func isConnecting(_ location: StorageLocation) -> Bool {
        connectingLocationID == location.id
    }
}
