//
//  LocationsSidebarView.swift
//  fichier
//

import SwiftUI
import UniformTypeIdentifiers
import FichierKit

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
    /// Binding controlling presentation of the new SMB connection sheet.
    @Binding var showingAddRemote: Bool
    
    /// Binding controlling presentation of the application settings sheet.
    @Binding var showingSettings: Bool
    
    /// Identifier of the storage location currently attempting connection, displaying an inline spinner.
    let connectingLocationID: String?
    
    /// Callback triggered when the user taps a storage location row.
    let onSelectLocation: (StorageLocation) -> Void
    
    /// Callback triggered when the user taps a discovered SMB share row.
    let onSelectShare: (MediaItem) -> Void
    
    /// Callback triggered when the user taps a folder node in the active drive's folder tree.
    let onSelectFolder: (MediaItem) -> Void

    @State private var viewModel: LocationsSidebarViewModel
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - manager: Shared storage location manager.
    ///   - showingAddRemote: Binding for connection sheet.
    ///   - showingSettings: Binding for settings sheet.
    ///   - connectingLocationID: Active connecting location ID.
    ///   - onSelectLocation: Location selection handler.
    ///   - onSelectShare: Share selection handler.
    ///   - onSelectFolder: Folder selection handler.
    public init(
        manager: StorageLocationManager,
        showingAddRemote: Binding<Bool>,
        showingSettings: Binding<Bool>,
        connectingLocationID: String?,
        onSelectLocation: @escaping (StorageLocation) -> Void,
        onSelectShare: @escaping (MediaItem) -> Void,
        onSelectFolder: @escaping (MediaItem) -> Void
    ) {
        self._showingAddRemote = showingAddRemote
        self._showingSettings = showingSettings
        self.connectingLocationID = connectingLocationID
        self.onSelectLocation = onSelectLocation
        self.onSelectShare = onSelectShare
        self.onSelectFolder = onSelectFolder
        // Note: SwiftUI view structs are transient and re-evaluated during parent updates.
        // While State(initialValue:) evaluates on every init, @State retains only the
        // original state object across renders and discards transient allocations.
        self._viewModel = State(initialValue: LocationsSidebarViewModel(manager: manager))
    }
    
    public var body: some View {
        List {
            Section {
                if viewModel.manager.allLocations.isEmpty {
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
                    ForEach(viewModel.sidebarItems) { item in
                        switch item {
                        case .location(let location):
                            locationRow(for: location)
                        case .share(let share):
                            shareRow(for: share)
                        }
                    }
                    .onDelete { indexSet in
                        let locationsToRemove = indexSet.compactMap { index -> StorageLocation? in
                            guard index < viewModel.sidebarItems.count,
                                  case .location(let loc) = viewModel.sidebarItems[index],
                                  loc.kind != .photos else { return nil }
                            return loc
                        }
                        guard !locationsToRemove.isEmpty else { return }
                        Task {
                            for location in locationsToRemove {
                                await viewModel.manager.removeLocation(location)
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
            
            if viewModel.manager.hasSelectedDrive {
                SidebarFolderTreeView(
                    manager: viewModel.manager,
                    onSelectFolder: onSelectFolder
                )
            }
        }
        .refreshable {
            if viewModel.manager.hasSelectedDrive {
                await viewModel.manager.refreshSharesAndFolders()
            }
        }
        #if os(tvOS)
        .listStyle(.plain)
        #else
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .fichierAtmosphericBackground()
        #endif
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
        #if !os(tvOS)
        .fileImporter(
            isPresented: $viewModel.showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let saved = try LocalStorageActor.createSavedFolderLocation(from: url)
                    viewModel.manager.addSavedFolderLocation(saved)
                    let loc = StorageLocation(folder: saved)
                    onSelectLocation(loc)
                } catch {
                    viewModel.handleFolderImportFailure(error.localizedDescription)
                }
            case .failure(let error):
                viewModel.handleFolderImportFailure(error.localizedDescription)
            }
        }
        #endif
        .alert(
            Text(.Strings.galleryErrorUnableToLoadFolder),
            isPresented: $viewModel.showingFolderErrorAlert,
            actions: {
                Button(.Strings.commonCancel, role: .cancel) {}
            },
            message: {
                Text(viewModel.folderPickerErrorMessage ?? "")
            }
        )
    }
    
    /// Content for the '+' location menu presenting options for local, cloud, and network locations.
    @ViewBuilder
    private var addLocationMenuContent: some View {
        Button {
            viewModel.presentFolderPicker()
        } label: {
            Label(.Strings.sidebarMenuAddIcloudFolder, systemImage: "icloud")
        }
        
        Button {
            viewModel.presentFolderPicker()
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
    
    // MARK: - Row Builders
    
    @ViewBuilder
    private func locationRow(for location: StorageLocation) -> some View {
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
                            .fill(FichierTheme.secondaryAccent)
                            .frame(width: 8, height: 8)
                        
                        Button {
                            Task {
                                await viewModel.manager.disconnect()
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
                        .fill(FichierTheme.secondaryAccent)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .deleteDisabled(location.kind == .photos)
        .contextMenu {
            if isCurrentLocation(location) && location.kind == .smb {
                Button(role: .destructive) {
                    Task {
                        await viewModel.manager.disconnect()
                    }
                } label: {
                    Label(.Strings.connectionButtonDisconnect, systemImage: "eject")
                }
            }
            if location.kind != .photos {
                Button(role: .destructive) {
                    Task {
                        await viewModel.manager.removeLocation(location)
                    }
                } label: {
                    Label(.Strings.sidebarActionRemoveLocation, systemImage: "trash")
                }
            }
        }
    }
    
    @ViewBuilder
    private func shareRow(for share: MediaItem) -> some View {
        Button {
            onSelectShare(share)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundColor(isShareSelected(share) ? .accentColor : .secondary)
                    .font(.body)
                    .frame(width: 20)
                
                Text(share.name)
                    .font(.subheadline)
                    .fontWeight(isShareSelected(share) ? .semibold : .regular)
                    .foregroundColor(isShareSelected(share) ? .primary : .secondary)
                    .lineLimit(1)
                
                Spacer()
                
                if isShareSelected(share) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.leading, 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .deleteDisabled(true)
    }
    
    private func isShareSelected(_ share: MediaItem) -> Bool {
        if let selectedShare = viewModel.manager.selectedShare {
            return selectedShare.id == share.id || selectedShare.shareName == share.shareName
        }
        return viewModel.manager.selectedFolder?.shareName == share.shareName
    }
    
    /// Tests whether the given location is currently active and connected.
    private func isCurrentLocation(_ location: StorageLocation) -> Bool {
        viewModel.manager.isConnected && viewModel.manager.currentLocation?.id == location.id
    }
    
    /// Tests whether the given location is currently establishing an asynchronous connection.
    private func isConnecting(_ location: StorageLocation) -> Bool {
        connectingLocationID == location.id
    }
}
