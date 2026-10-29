//
//  SMBConnectWithDiscoveryView.swift
//  fichier
//

import SwiftUI

struct SMBConnectWithDiscoveryView: View {
    var smbManager: SMBDirectManager
    @State private var discovery = SMBHostDiscovery()
    
    @State private var selectedHost = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showingSettings = false
    
    var body: some View {
        NavigationStack {
            Form {
                // 0. Saved Validated Connections Section
                if !smbManager.savedConnections.isEmpty {
                    Section(.Strings.connectionSectionSavedServers) {
                        ForEach(smbManager.savedConnections) { saved in
                            Button {
                                selectedHost = saved.host
                                username = saved.username
                                password = smbManager.password(for: saved)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                Task {
                                    await smbManager.connect(
                                        host: selectedHost,
                                        user: username,
                                        pass: password
                                    )
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "externaldrive.connected.to.line.below.fill")
                                        .foregroundColor(.blue)
                                        .font(.title3)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(saved.host)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text(.Strings.connectionSavedServerUser(saved.username))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedHost == saved.host && username == saved.username && smbManager.isLoading {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .foregroundColor(.blue.opacity(0.8))
                                    }
                                }
                            }
                            .disabled(smbManager.isLoading)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                let conn = smbManager.savedConnections[index]
                                smbManager.removeSavedConnection(conn)
                            }
                        }
                    }
                }
                
                // 1. Bonjour Local Network Discovery Section
                Section {
                    if discovery.isScanning && discovery.discoveredHosts.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(.Strings.connectionSearchingLocalNetwork)
                                .foregroundColor(.secondary)
                        }
                    } else if discovery.discoveredHosts.isEmpty {
                        HStack {
                            Text(.Strings.connectionNoServersFound)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(.Strings.connectionButtonScan) {
                                discovery.startDiscovery()
                            }
                        }
                    } else {
                        ForEach(discovery.discoveredHosts) { host in
                            Button {
                                if let ipv4 = host.resolvedHost {
                                    selectedHost = ipv4
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "macmini.fill")
                                        .foregroundColor(.blue)
                                        .font(.title3)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(host.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        if let ipv4 = host.resolvedHost {
                                            Text(ipv4)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text(.Strings.connectionResolvingAddress)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if let ipv4 = host.resolvedHost, selectedHost == ipv4 {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .disabled(host.resolvedHost == nil)
                        }
                    }
                } header: {
                    HStack {
                        Text(.Strings.connectionSectionDiscoveredServers)
                        Spacer()
                        Button {
                            discovery.startDiscovery()
                        } label: {
                            Label(.Strings.connectionButtonRefresh, systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                }
                
                // 2. Credentials & Manual Host Input
                Section(.Strings.connectionSectionServerCredentials) {
                    TextField(.Strings.connectionFieldHostAddress, text: $selectedHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                    
                    TextField(.Strings.connectionFieldMacUsername, text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    SecureField(.Strings.connectionFieldMacPassword, text: $password)
                }
                
                // 3. Error Display
                if let error = smbManager.errorMessage ?? discovery.errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
                
                // 4. Connect Button
                Section {
                    Button {
                        Task {
                            await smbManager.connect(
                                host: selectedHost,
                                user: username,
                                pass: password
                            )
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if smbManager.isLoading {
                                ProgressView()
                            } else {
                                Text(.Strings.connectionButtonConnectListShares)
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(selectedHost.isEmpty || username.isEmpty || smbManager.isLoading)
                }
            }
            .navigationTitle(.Strings.connectionTitleMacMiniPhotos)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(.Strings.settingsTitle)
                }
            }
            .sheet(isPresented: $showingSettings) {
                AppSettingsView()
            }
            .onAppear {
                discovery.startDiscovery()
                if selectedHost.isEmpty, let mostRecent = smbManager.savedConnections.first {
                    selectedHost = mostRecent.host
                    username = mostRecent.username
                    password = smbManager.password(for: mostRecent)
                }
            }
            .onDisappear {
                discovery.stopDiscovery()
            }
        }
    }
}
