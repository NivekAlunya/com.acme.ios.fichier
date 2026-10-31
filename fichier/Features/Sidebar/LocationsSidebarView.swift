//
//  LocationsSidebarView.swift
//  fichier
//

import SwiftUI
import UniformTypeIdentifiers

public struct LocationsSidebarView: View {
    @Bindable var manager: SMBDirectManager
    @Binding var showingAddRemote: Bool
    @Binding var showingSettings: Bool
    let connectingLocationID: String?
    let onSelectLocation: (StorageLocation) -> Void
    
    @State private var showingFolderPicker = false
    @State private var folderPickerErrorMessage: String?
    @State private var showingFolderErrorAlert = false
    
    public init(
        manager: SMBDirectManager,
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
                            
                            Button {
                                showingAddRemote = true
                            } label: {
                                Label(.Strings.sidebarMenuConnectSmb, systemImage: "macmini")
                            }
                        } label: {
                            Text(.Strings.sidebarMenuAddLocation)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ForEach(manager.allLocations) { location in
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
                                
                                if isConnecting(location) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else if isCurrentLocation(location) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        let locationsToRemove = indexSet.map { manager.allLocations[$0] }
                        for loc in locationsToRemove {
                            manager.removeLocation(loc)
                        }
                    }
                }
            } header: {
                HStack {
                    Text(.Strings.sidebarSectionLocations)
                    Spacer()
                    Menu {
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
            if manager.isConnected {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(.Strings.connectionButtonDisconnect, role: .destructive) {
                        manager.disconnect()
                    }
                }
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
            "Folder Selection Failed",
            isPresented: $showingFolderErrorAlert,
            actions: {
                Button(.Strings.commonCancel, role: .cancel) {}
            },
            message: {
                Text(folderPickerErrorMessage ?? "")
            }
        )
    }
    
    private func isCurrentLocation(_ location: StorageLocation) -> Bool {
        manager.isConnected && manager.currentConnectionID == location.id
    }
    
    private func isConnecting(_ location: StorageLocation) -> Bool {
        connectingLocationID == location.id
    }
}
