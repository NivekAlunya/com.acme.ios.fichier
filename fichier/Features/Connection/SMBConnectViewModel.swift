//
//  SMBConnectViewModel.swift
//  fichier
//

import Foundation
import Observation
import FichierKit

/// ViewModel managing Bonjour discovery, manual SMB credentials, and connection state
/// for ``SMBConnectWithDiscoveryView``.
@Observable
@MainActor
final class SMBConnectViewModel {
    // MARK: - Dependencies

    private let smbManager: StorageLocationManager
    let discovery: any SMBHostDiscoveryProtocol

    // MARK: - Form State

    /// User-entered or Bonjour-selected server IP address or hostname.
    var selectedHost = ""

    /// Optional user-friendly display name for the server.
    var selectedHostname = ""

    /// SMB authentication username.
    var username = ""

    /// Plaintext SMB authentication password.
    var password = ""

    // MARK: - Derived State

    var isLoading: Bool {
        smbManager.isLoading
    }

    var isConnected: Bool {
        smbManager.isConnected
    }

    var errorMessage: String? {
        smbManager.errorMessage ?? discovery.errorMessage
    }

    var isConnectDisabled: Bool {
        selectedHost.isEmpty || username.isEmpty || smbManager.isLoading
    }

    // MARK: - Initialization

    init(
        smbManager: StorageLocationManager,
        discovery: any SMBHostDiscoveryProtocol = SMBHostDiscovery()
    ) {
        self.smbManager = smbManager
        self.discovery = discovery
    }

    // MARK: - Actions

    func startDiscovery() {
        discovery.startDiscovery()
    }

    func stopDiscovery() {
        discovery.stopDiscovery()
    }

    func selectDiscoveredHost(_ host: DiscoveredHost) {
        guard let ipv4 = host.resolvedHost else { return }
        selectedHost = ipv4
        selectedHostname = host.name
    }

    func resolvedFinalHostname() -> String? {
        let trimmed = selectedHostname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return discovery.discoveredHosts.first(where: { $0.resolvedHost == selectedHost })?.name
    }

    func connect() async {
        await smbManager.connect(
            host: selectedHost,
            user: username,
            pass: password,
            hostname: resolvedFinalHostname()
        )
    }
}
