//
//  SMBConnectWithDiscoveryView.swift
//  com.acme.ios.photos
//
//  Created by Kevin LAUNAY on 27/10/2026.
//

import SwiftUI

public struct SMBConnectWithDiscoveryView: View {
    var smbManager: SMBDirectManager
    @State private var discovery = SMBHostDiscovery()
    
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    
    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - Saved Validated Connections Section
                if !smbManager.savedConnections.isEmpty {
                    Section("Saved Servers") {
                        ForEach(smbManager.savedConnections) { saved in
                            Button {
                                let savedPassword = smbManager.password(for: saved)
                                self.host = saved.host
                                self.username = saved.username
                                self.password = savedPassword
                                
                                Task {
                                    discovery.stopDiscovery()
                                    await smbManager.connect(
                                        host: saved.host,
                                        user: saved.username,
                                        pass: savedPassword
                                    )
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "externaldrive.connected.to.line.below.fill")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(saved.host)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text("User: \(saved.username)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let item = smbManager.savedConnections[index]
                                smbManager.removeSavedConnection(item)
                            }
                        }
                    }
                }
                
                // MARK: - Auto-Discovered Hosts Section (IPv4)
                Section {
                    if discovery.isScanning && discovery.discoveredHosts.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Searching local network for Macs (IPv4)...")
                                .foregroundColor(.secondary)
                        }
                    } else if discovery.discoveredHosts.isEmpty {
                        HStack {
                            Text("No SMB servers found yet")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Scan") { discovery.startDiscovery() }
                        }
                    } else {
                        ForEach(discovery.discoveredHosts) { server in
                            Button {
                                if let ipv4 = server.resolvedHost {
                                    self.host = ipv4
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "desktopcomputer")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text(server.resolvedHost ?? "Resolving IPv4 address...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if let ipv4 = server.resolvedHost, host == ipv4 {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .disabled(server.resolvedHost == nil)
                        }
                    }
                } header: {
                    HStack {
                        Text("Discovered Servers")
                        Spacer()
                        if discovery.isScanning {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Button("Refresh") { discovery.startDiscovery() }
                                .font(.caption)
                        }
                    }
                }
                
                // MARK: - Server Credentials (No Share Name Needed!)
                Section("Server Credentials (IPv4)") {
                    TextField("Host IPv4 (e.g. 192.168.1.50)", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    TextField("Mac Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    SecureField("Mac Password", text: $password)
                }
                
                if let error = smbManager.errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Button {
                    Task {
                        discovery.stopDiscovery()
                        await smbManager.connect(host: host, user: username, pass: password)
                    }
                } label: {
                    if smbManager.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Text("Connect & List Shares")
                            .frame(maxWidth: .infinity)
                            .bold()
                    }
                }
                .disabled(host.isEmpty || username.isEmpty || smbManager.isLoading)
            }
            .navigationTitle("Mac mini Photos")
            .refreshable {
                discovery.startDiscovery()
            }
            .onAppear {
                if host.isEmpty, let last = smbManager.savedConnections.first {
                    host = last.host
                    username = last.username
                    password = smbManager.password(for: last)
                }
                discovery.startDiscovery()
            }
            .onDisappear {
                discovery.stopDiscovery()
            }
        }
    }
}
