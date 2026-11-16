//
//  SMBConnectWithDiscoveryView.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Modal sheet presenting local network Bonjour discovery alongside manual SMB connection inputs.
///
/// Provides a guided connection workflow:
/// 1. Continuously scans the local Wi-Fi / Ethernet subnet using `SMBHostDiscovery` for `_smb._tcp` endpoints.
/// 2. Allows selecting a discovered server to auto-fill its resolved IPv4 address and Bonjour display name.
/// 3. Accepts manual host address, username, and password credentials.
/// 4. Validates connection against `StorageLocationManager` and dismisses upon successful authentication.
struct SMBConnectWithDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: SMBConnectViewModel

    init(smbManager: StorageLocationManager) {
        // Note: SwiftUI view structs are transient and re-evaluated during parent updates.
        // While State(initialValue:) evaluates on every init, @State retains only the
        // original state object across renders and discards transient allocations.
        _viewModel = State(initialValue: SMBConnectViewModel(smbManager: smbManager))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 1. Bonjour Local Network Discovery Section
                Section {
                    if viewModel.discovery.isScanning && viewModel.discovery.discoveredHosts.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(.Strings.connectionSearchingLocalNetwork)
                                .foregroundColor(.secondary)
                        }
                    } else if viewModel.discovery.discoveredHosts.isEmpty {
                        HStack {
                            Text(.Strings.connectionNoServersFound)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(.Strings.connectionButtonScan) {
                                viewModel.startDiscovery()
                            }
                        }
                    } else {
                        ForEach(viewModel.discovery.discoveredHosts) { host in
                            Button {
                                viewModel.selectDiscoveredHost(host)
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
                                    
                                    if let ipv4 = host.resolvedHost, viewModel.selectedHost == ipv4 {
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
                            viewModel.startDiscovery()
                        } label: {
                            Label(.Strings.connectionButtonRefresh, systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                }
                
                // 2. Credentials & Manual Host Input
                Section(.Strings.connectionSectionServerCredentials) {
                    TextField(.Strings.connectionFieldServerName, text: $viewModel.selectedHostname)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    
                    TextField(.Strings.connectionFieldHostAddress, text: $viewModel.selectedHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                    
                    TextField(.Strings.connectionFieldMacUsername, text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    SecureField(.Strings.connectionFieldMacPassword, text: $viewModel.password)
                }
                
                // 3. Error Display
                if let error = viewModel.errorMessage {
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
                            await viewModel.connect()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isLoading {
                                ProgressView()
                            } else {
                                Text(.Strings.connectionButtonConnectListShares)
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(viewModel.isConnectDisabled)
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
            }
            .onChange(of: viewModel.isConnected) { _, isConnected in
                if isConnected {
                    dismiss()
                }
            }
            .onAppear {
                viewModel.startDiscovery()
            }
            .onDisappear {
                viewModel.stopDiscovery()
            }
        }
    }
}
