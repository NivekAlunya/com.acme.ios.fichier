//
//  SMBConnectViewModelTests.swift
//  fichierTests
//

import Testing
import FichierKit
@testable import fichier

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

    @Test("isConnectDisabled requires non-empty host and username")
    func connectValidation() {
        let viewModel = SMBConnectViewModel(
            smbManager: StorageLocationManager(),
            discovery: StubSMBHostDiscovery()
        )

        #expect(viewModel.isConnectDisabled)

        viewModel.selectedHost = "192.168.1.10"
        #expect(viewModel.isConnectDisabled)

        viewModel.username = "alice"
        #expect(!viewModel.isConnectDisabled)
    }

    @Test("resolvedFinalHostname prefers trimmed selectedHostname and falls back to discovered host name")
    func resolvedFinalHostname() {
        let discovered = DiscoveredHost(name: "Studio NAS", resolvedHost: "192.168.1.20")
        let discovery = StubSMBHostDiscovery(discoveredHosts: [discovered])
        let viewModel = SMBConnectViewModel(
            smbManager: StorageLocationManager(),
            discovery: discovery
        )

        viewModel.selectedHost = "192.168.1.20"
        viewModel.selectedHostname = "   "
        #expect(viewModel.resolvedFinalHostname() == "Studio NAS")

        viewModel.selectedHostname = "  Custom Name  "
        #expect(viewModel.resolvedFinalHostname() == "Custom Name")
    }

    @Test("errorMessage surfaces discovery error when smbManager has no error")
    func errorMessagePropagation() {
        let discovery = StubSMBHostDiscovery(errorMessage: "Discovery failed")
        let viewModel = SMBConnectViewModel(
            smbManager: StorageLocationManager(),
            discovery: discovery
        )

        #expect(viewModel.errorMessage == "Discovery failed")
    }
}
