//
//  StubSMBServerStore.swift
//  FichierTVTests
//
//

import Foundation
import FichierKit

actor StubSMBServerStore: SMBServerStoreProtocol {
    private var servers: [SavedSMBConnection]
    private var passwords: [String: String]
    private var statuses: [String: ServerConnectionStatus]

    init(
        servers: [SavedSMBConnection] = [],
        passwords: [String: String] = [:],
        statuses: [String: ServerConnectionStatus] = [:]
    ) {
        self.servers = servers
        self.passwords = passwords
        self.statuses = statuses
    }

    func loadServers() async -> [SavedSMBConnection] {
        servers.sorted { $0.lastConnected > $1.lastConnected }
    }

    func saveServer(_ server: SavedSMBConnection, password: String) async throws {
        servers.removeAll { $0.id == server.id }
        servers.insert(server, at: 0)
        passwords[server.id] = password
    }

    func removeServer(_ server: SavedSMBConnection) async throws {
        servers.removeAll { $0.id == server.id }
        passwords.removeValue(forKey: server.id)
    }

    func password(for server: SavedSMBConnection) async -> String? {
        passwords[server.id]
    }

    func checkServerStatus(_ server: SavedSMBConnection) async -> ServerConnectionStatus {
        statuses[server.id] ?? .offline
    }
}
