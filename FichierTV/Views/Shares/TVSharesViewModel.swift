//
//  TVSharesViewModel.swift
//  FichierTV
//

import Foundation
import Observation
import FichierKit

/// State coordinator managing the list of configured SMB server cards and live reachability probes.
@Observable
@MainActor
public final class TVSharesViewModel {
    public private(set) var serverCards: [ServerCardItem] = []
    public private(set) var isLoading: Bool = false
    public var selectedServerForAction: ServerCardItem?
    public var showingActionSheet: Bool = false

    private let store: any SMBServerStoreProtocol
    private let resolver: any MediaSourceResolverProtocol

    public init(
        store: any SMBServerStoreProtocol = DefaultSMBServerStore.shared,
        resolver: any MediaSourceResolverProtocol = DefaultMediaSourceResolver.shared
    ) {
        self.store = store
        self.resolver = resolver
    }

    /// Loads saved servers from persistence and triggers parallel reachability scans.
    public func loadServers() async {
        isLoading = true
        let connections = await store.loadServers()

        self.serverCards = connections.map { conn in
            ServerCardItem(connection: conn, status: .connecting)
        }
        isLoading = false

        await probeReachability(for: connections)
    }

    /// Removes a server from persistent storage, invalidates its active resolver cache, and updates visible cards.
    public func removeServer(_ server: SavedSMBConnection) async {
        try? await store.removeServer(server)
        await resolver.invalidateSource(id: server.id)
        serverCards.removeAll { $0.id == server.id }
        if selectedServerForAction?.id == server.id {
            selectedServerForAction = nil
        }
    }

    private func probeReachability(for connections: [SavedSMBConnection]) async {
        await withTaskGroup(of: (String, ServerConnectionStatus).self) { group in
            for conn in connections {
                group.addTask { [store] in
                    let status = await store.checkServerStatus(conn)
                    return (conn.id, status)
                }
            }

            for await (id, status) in group {
                if let index = serverCards.firstIndex(where: { $0.id == id }) {
                    let existing = serverCards[index]
                    serverCards[index] = ServerCardItem(connection: existing.connection, status: status)
                }
            }
        }
    }
}
