//
//  SavedSMBConnection.swift
//  fichier
//

import Foundation

nonisolated public struct SavedSMBConnection: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(username)@\(host)" }
    public let host: String
    public let username: String
    public let lastConnected: Date
    
    public init(host: String, username: String, lastConnected: Date) {
        self.host = host
        self.username = username
        self.lastConnected = lastConnected
    }
}
