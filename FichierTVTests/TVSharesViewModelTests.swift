//
//  TVSharesViewModelTests.swift
//  FichierTVTests
//
//

import Foundation
import Testing
@testable import FichierTV
import FichierKit

@Suite("TVSharesViewModel Tests")
struct TVSharesViewModelTests {
    @Test("Loads saved servers, probes reachability, and supports server removal")
    @MainActor
    func testLoadAndRemoveServers() async {
        let macMini = SavedSMBConnection(
            host: "192.168.1.50",
            username: "kevin",
            lastConnected: Date(),
            hostname: "Mac mini"
        )
        let nas = SavedSMBConnection(
            host: "192.168.1.60",
            username: "admin",
            lastConnected: Date().addingTimeInterval(-3600),
            hostname: "Home NAS"
        )

        let store = StubSMBServerStore(
            servers: [macMini, nas],
            statuses: [
                macMini.id: .online,
                nas.id: .offline
            ]
        )

        let viewModel = TVSharesViewModel(store: store)
        await viewModel.loadServers()

        #expect(viewModel.serverCards.count == 2)
        #expect(viewModel.serverCards[0].id == macMini.id)
        #expect(viewModel.serverCards[0].status == .online)
        #expect(viewModel.serverCards[1].id == nas.id)
        #expect(viewModel.serverCards[1].status == .offline)

        await viewModel.removeServer(macMini)
        #expect(viewModel.serverCards.count == 1)
        #expect(viewModel.serverCards[0].id == nas.id)
        #expect(await store.loadServers().count == 1)
    }
}
