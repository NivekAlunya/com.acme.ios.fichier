//
//  TVServerFormViewModelTests.swift
//  FichierTVTests
//
//

import Foundation
import Testing
@testable import FichierTV
import FichierKit

@Suite("TVServerFormViewModel Tests")
struct TVServerFormViewModelTests {
    @Test("Starts Bonjour discovery on load, selects resolved hosts, and ignores unresolved hosts")
    @MainActor
    func testBonjourHostSelectionAndLifecycle() async {
        let unresolved = DiscoveredHost(name: "Resolving NAS", resolvedHost: nil)
        let macMini = DiscoveredHost(name: "Mac mini", resolvedHost: "192.168.1.50")
        let discovery = StubSMBHostDiscovery(discoveredHosts: [unresolved, macMini])
        let store = StubSMBServerStore()

        let viewModel = TVServerFormViewModel(
            mode: .add,
            store: store,
            validator: StubSMBConnectionValidator(),
            discovery: discovery,
            resolver: StubMediaSourceResolver()
        )

        await viewModel.loadInitialState()
        #expect(discovery.startCount == 1)
        #expect(discovery.isScanning)

        viewModel.selectDiscoveredHost(unresolved)
        #expect(viewModel.model.host.isEmpty)

        viewModel.selectDiscoveredHost(macMini)
        #expect(viewModel.model.host == "192.168.1.50")
        #expect(viewModel.model.hostname == "Mac mini")
        #expect(viewModel.isSelectedDiscoveredHost(macMini))

        viewModel.stopDiscovery()
        #expect(discovery.stopCount == 1)
        #expect(!discovery.isScanning)
    }

    @Test("Save validates SMB shares first and refuses persistence when authentication fails")
    @MainActor
    func testSaveBlockedWhenSMBValidationFails() async {
        let store = StubSMBServerStore()
        let discovery = StubSMBHostDiscovery()
        let validator = StubSMBConnectionValidator(error: .badCredentials)

        let viewModel = TVServerFormViewModel(
            mode: .add,
            store: store,
            validator: validator,
            discovery: discovery,
            resolver: StubMediaSourceResolver()
        )

        viewModel.model.host = "192.168.1.50"
        viewModel.model.username = "kevin"
        viewModel.model.password = "wrong"

        let saved = await viewModel.save()
        #expect(!saved)
        #expect(viewModel.errorMessage == SMBError.badCredentials.errorDescription)
        #expect(await store.loadServers().isEmpty)
    }

    @Test("Save persists server after share validation and removes superseded record on edit")
    @MainActor
    func testSaveValidatesAndReplacesEditedServer() async {
        let previous = SavedSMBConnection(
            host: "192.168.1.40",
            username: "olduser",
            lastConnected: Date().addingTimeInterval(-3600),
            hostname: "Old Mac"
        )
        let store = StubSMBServerStore(
            servers: [previous],
            passwords: [previous.id: "oldpass"]
        )
        let resolver = StubMediaSourceResolver()
        let discovery = StubSMBHostDiscovery(
            discoveredHosts: [DiscoveredHost(name: "Studio Mac", resolvedHost: "192.168.1.55")]
        )

        let viewModel = TVServerFormViewModel(
            mode: .edit(previous),
            store: store,
            validator: StubSMBConnectionValidator(shares: ["Media", "Photos"]),
            discovery: discovery,
            resolver: resolver
        )

        await viewModel.loadInitialState()
        #expect(viewModel.model.host == "192.168.1.40")
        #expect(viewModel.model.username == "olduser")
        #expect(viewModel.model.password == "oldpass")

        viewModel.model.host = "smb://192.168.1.55"
        viewModel.model.username = "kevin"
        viewModel.model.password = "secret"

        let saved = await viewModel.save()
        #expect(saved)
        #expect(viewModel.errorMessage == nil)

        let storedServers = await store.loadServers()
        #expect(storedServers.count == 1)
        #expect(storedServers[0].id == "kevin@192.168.1.55")
        #expect(await store.password(for: storedServers[0]) == "secret")
        #expect(await resolver.invalidatedIDs == [previous.id, "kevin@192.168.1.55"])
    }
}
