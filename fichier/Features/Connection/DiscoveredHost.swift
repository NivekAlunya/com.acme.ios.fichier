//
//  DiscoveredHost.swift
//  com.acme.ios.photos
//
//  Created by Kevin LAUNAY on 27/10/2026.
//

import Foundation
import Network

/// Represents a Bonjour-advertised SMB service discovered on the local area network.
///
/// Captured by `SMBHostDiscovery` using Network framework's `NWBrowser`, containing
/// the advertised Bonjour service name, resolved IPv4 address, and network endpoint.
public struct DiscoveredHost: Identifiable, Hashable, Sendable {
    /// Unique identifier composed of the advertised service name and resolved IP address.
    public var id: String { "\(name)_\(resolvedHost ?? "")" }
    
    /// User-friendly advertised Bonjour service name (e.g. "Kevin's Mac mini").
    public let name: String
    
    /// Resolved IPv4 address string (e.g. "192.168.1.50"), or `nil` while DNS resolution is in progress.
    public var resolvedHost: String?
    
    /// Network endpoint descriptor used by `NWConnection` to probe and resolve IP connectivity.
    public let endpoint: NWEndpoint
    
    /// Memberwise initializer for a discovered host entry.
    ///
    /// - Parameters:
    ///   - name: Advertised service name.
    ///   - resolvedHost: Resolved IP address.
    ///   - endpoint: Underlying Network endpoint.
    public init(name: String, resolvedHost: String? = nil, endpoint: NWEndpoint) {
        self.name = name
        self.resolvedHost = resolvedHost
        self.endpoint = endpoint
    }
}
