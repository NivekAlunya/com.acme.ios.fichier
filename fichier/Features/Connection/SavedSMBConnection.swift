//
//  SavedSMBConnection.swift
//  fichier
//

import Foundation

/// Persisted configuration record representing a previously validated SMB server connection.
///
/// Stores server host address, user identity, last connection timestamp, and optional display hostname.
/// Passwords are intentionally omitted from this model and stored securely in the system Keychain (`SMBKeychain`).
nonisolated public struct SavedSMBConnection: Identifiable, Codable, Hashable, Sendable {
    /// Unique compound identifier formatted as `username@host`.
    public var id: String { "\(username)@\(host)" }
    
    /// Target server IP address or network domain name.
    public let host: String
    
    /// User account name for SMB session authentication (empty for guest).
    public let username: String
    
    /// Timestamp of the most recent successful connection, used for sorting.
    public let lastConnected: Date
    
    /// User-friendly or Bonjour-resolved hostname (e.g. "Mac mini de Kevin").
    public let hostname: String?
    
    /// Initializes a new saved connection record.
    ///
    /// - Parameters:
    ///   - host: Hostname or IP address.
    ///   - username: SMB account username.
    ///   - lastConnected: Date when connection was established.
    ///   - hostname: Optional display name.
    public init(host: String, username: String, lastConnected: Date, hostname: String? = nil) {
        self.host = host
        self.username = username
        self.lastConnected = lastConnected
        self.hostname = hostname
    }
    
    /// User-facing display title combining the hostname and IP address when distinct.
    public var displayName: String {
        if let hostname = hostname?.trimmingCharacters(in: .whitespacesAndNewlines), !hostname.isEmpty, hostname != host {
            return "\(hostname) [\(host)]"
        } else {
            return host
        }
    }
}
