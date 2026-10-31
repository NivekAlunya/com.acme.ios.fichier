//
//  SMBConnectWithDiscoveryView.swift
//  fichier
//

import SwiftUI

struct SMBConnectWithDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    var smbManager: SMBDirectManager
    @State private var discovery = SMBHostDiscovery()
    
    @State private var selectedHost = ""
    @State private var selectedHostname = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showingSettings = false
    
    var body: some View {
        NavigationStack {
            Form {
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
                                    selectedHostname = host.name
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
                    TextField(.Strings.connectionFieldServerName, text: $selectedHostname)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    
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
                        let finalHostname: String? = {
                            let trimmed = selectedHostname.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty { return trimmed }
                            return discovery.discoveredHosts.first(where: { $0.resolvedHost == selectedHost })?.name
                        }()
                        
                        Task {
                            await smbManager.connect(
                                host: selectedHost,
                                user: username,
                                pass: password,
                                hostname: finalHostname
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
            .navigationTitle(.Strings.connectionTitleConnectToServer)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(.Strings.commonCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(.Strings.settingsTitle)
                }
            }
            .onChange(of: smbManager.isConnected) { _, isConnected in
                if isConnected {
                    dismiss()
                }
            }
            .sheet(isPresented: $showingSettings) {
                AppSettingsView()
            }
            .onAppear {
                discovery.startDiscovery()
            }
            .onDisappear {
                discovery.stopDiscovery()
            }
        }
    }
}
