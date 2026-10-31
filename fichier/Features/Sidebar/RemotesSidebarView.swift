//
//  RemotesSidebarView.swift
//  fichier
//

import SwiftUI

public struct RemotesSidebarView: View {
    @Bindable var manager: SMBDirectManager
    @Binding var showingAddRemote: Bool
    @Binding var showingSettings: Bool
    let connectingRemoteID: String?
    let onSelectRemote: (SavedSMBConnection) -> Void
    
    public init(
        manager: SMBDirectManager,
        showingAddRemote: Binding<Bool>,
        showingSettings: Binding<Bool>,
        connectingRemoteID: String?,
        onSelectRemote: @escaping (SavedSMBConnection) -> Void
    ) {
        self.manager = manager
        self._showingAddRemote = showingAddRemote
        self._showingSettings = showingSettings
        self.connectingRemoteID = connectingRemoteID
        self.onSelectRemote = onSelectRemote
    }
    
    public var body: some View {
        List {
            Section {
                if manager.savedConnections.isEmpty {
                    ContentUnavailableView {
                        Label(
                            String(localized: .Strings.sidebarNoSavedRemotesTitle),
                            systemImage: "externaldrive.badge.plus"
                        )
                    } description: {
                        Text(.Strings.sidebarNoSavedRemotesDescription)
                    } actions: {
                        Button {
                            showingAddRemote = true
                        } label: {
                            Text(.Strings.sidebarButtonAddRemote)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ForEach(manager.savedConnections) { saved in
                        Button {
                            onSelectRemote(saved)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isCurrentConnection(saved) ? "externaldrive.connected.to.line.below.fill" : "externaldrive.fill")
                                    .foregroundColor(isCurrentConnection(saved) ? .blue : .secondary)
                                    .font(.title3)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(saved.displayName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    Text(.Strings.connectionSavedServerUser(saved.username))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if isConnecting(saved) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else if isCurrentConnection(saved) {
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
                        for index in indexSet {
                            let conn = manager.savedConnections[index]
                            if manager.currentConnectionID == conn.id {
                                manager.disconnect()
                            }
                            manager.removeSavedConnection(conn)
                        }
                    }
                }
            } header: {
                HStack {
                    Text(.Strings.sidebarSectionRemotes)
                    Spacer()
                    Button {
                        showingAddRemote = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(.Strings.sidebarButtonAddRemote)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(.Strings.sidebarTitleRemotes)
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
    }
    
    private func isCurrentConnection(_ saved: SavedSMBConnection) -> Bool {
        manager.isConnected && manager.currentConnectionID == saved.id
    }
    
    private func isConnecting(_ saved: SavedSMBConnection) -> Bool {
        connectingRemoteID == saved.id
    }
}
