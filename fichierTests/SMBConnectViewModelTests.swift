//
//  SMBConnectViewModelTests.swift
//  fichierTests
//

import Testing
import FichierKit
@testable import Fichier

@Suite("SMBConnectViewModel")
@MainActor
struct SMBConnectViewModelTests {
    @Test("startDiscovery and stopDiscovery forward to discovery")
    func discoveryLifecycle() {
        let discovery = StubSMBHostDiscovery()
        let viewModel = SMBConnectViewModel(
            smbManager: StorageLocationManager(),
            discovery: discovery
        )

        viewModel.startDiscovery()
        #expect(discovery.startCount == 1)
        #expect(discovery.isScanning)

        viewModel.stopDiscovery()
        #expect(discovery.stopCount == 1)
        #expect(!discovery.isScanning)
    }

    @Test("selectDiscoveredHost populates host and hostname when resolvedHost is present")
    func selectDiscoveredHost() {
        let resolved = DiscoveredHost(name: "Mac Mini", resolvedHost: "192.168.1.10")
        let unresolved = DiscoveredHost(name: "NAS", resolvedHost: nil)
        let discovery = StubSMBHostDiscovery(discoveredHosts: [resolved, unresolved])
        let viewModel = SMBConnectViewModel(
            smbManager: StorageLocationManager(),
            discovery: discovery
        )

        viewModel.selectDiscoveredHost(unresolved)
        #expect(viewModel.selectedHost.isEmpty)
        #expect(viewModel.selectedHostname.isEmpty)

        viewModel.selectDiscoveredHost(resolved)
        #expect(viewModel.selectedHost == "192.168.1.10")
        #expect(viewModel.selectedHostname == "Mac Mini")
    }

    @Test("isConnectDisabled validates host, username, and manager loading state")
    func isConnectDisabledValidation() {
        let manager = StorageLocationManager()
        let viewModel = SMBConnectViewModel(
            smbManager: manager,
            discovery: StubSMBHostDiscovery()
        )

        // 1. Both host and username empty
        #expect(viewModel.isConnectDisabled)

        // 2. Only host provided
        viewModel.selectedHost = "192.168.1.10"
        viewModel.username = ""
        #expect(viewModel.isConnectDisabled)

        // 3. Only username provided
        viewModel.selectedHost = ""
        viewModel.username = "alice"
        #expect(viewModel.isConnectDisabled)

        // 4. Both host and username provided, not loading
        viewModel.selectedHost = "192.168.1.10"
        viewModel.username = "alice"
        manager.isLoading = false
        #expect(!viewModel.isConnectDisabled)

        // 5. Both provided, but manager is actively loading
        manager.isLoading = true
        #expect(viewModel.isConnectDisabled)

        // 6. Loading completes
        manager.isLoading = false
        #expect(!viewModel.isConnectDisabled)
    }

    @Test("resolvedFinalHostname prioritizes manual hostname, falls back to discovered host, or returns nil")
    func resolvedFinalHostnameResolution() {
        let discovered1 = DiscoveredHost(name: "Studio NAS", resolvedHost: "192.168.1.20")
        let discovered2 = DiscoveredHost(name: "Backup Server", resolvedHost: "192.168.1.30")
        let discovery = StubSMBHostDiscovery(discoveredHosts: [discovered1, discovered2])
        let viewModel = SMBConnectViewModel(
            smbManager: StorageLocationManager(),
            discovery: discovery
        )

        // 1. Manually entered hostname takes priority and is trimmed
        viewModel.selectedHost = "192.168.1.20"
        viewModel.selectedHostname = "  Workstation  "
        #expect(viewModel.resolvedFinalHostname() == "Workstation")

        // 2. Whitespace-only hostname falls back to discovered host matching selectedHost
        viewModel.selectedHostname = "   \n\t  "
        #expect(viewModel.resolvedFinalHostname() == "Studio NAS")

        // 3. Empty hostname falls back to discovered host matching selectedHost
        viewModel.selectedHostname = ""
        viewModel.selectedHost = "192.168.1.30"
        #expect(viewModel.resolvedFinalHostname() == "Backup Server")

        // 4. Empty hostname with unknown/manual IP falls back to nil
        viewModel.selectedHost = "10.0.0.99"
        viewModel.selectedHostname = ""
        #expect(viewModel.resolvedFinalHostname() == nil)
    }

    @Test("connect sanitizes password from memory after execution")
    func passwordSanitizationOnConnect() async {
        let manager = StorageLocationManager()
        let viewModel = SMBConnectViewModel(
            smbManager: manager,
            discovery: StubSMBHostDiscovery()
        )

        viewModel.selectedHost = "192.168.1.50"
        viewModel.username = "admin"
        viewModel.password = "secret_password_123"

        #expect(viewModel.password == "secret_password_123")

        await viewModel.connect()

        #expect(viewModel.password.isEmpty)
    }

    @Test("derived state forwards loading, connection, and errors appropriately")
    func stateForwarding() {
        let manager = StorageLocationManager()
        let discovery = StubSMBHostDiscovery()
        let viewModel = SMBConnectViewModel(
            smbManager: manager,
            discovery: discovery
        )

        // Loading forwarding
        manager.isLoading = true
        #expect(viewModel.isLoading)
        manager.isLoading = false
        #expect(!viewModel.isLoading)

        // Connection forwarding
        manager.isConnected = true
        #expect(viewModel.isConnected)
        manager.isConnected = false
        #expect(!viewModel.isConnected)

        // Error message forwarding: manager error takes precedence
        manager.errorMessage = "Auth failed"
        discovery.errorMessage = "DNS error"
        #expect(viewModel.errorMessage == "Auth failed")

        // Falls back to discovery error when manager has no error
        manager.errorMessage = nil
        #expect(viewModel.errorMessage == "DNS error")

        // Nil when neither has an error
        discovery.errorMessage = nil
        #expect(viewModel.errorMessage == nil)
    }
}
