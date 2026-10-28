//
//  DiscoveredHost.swift
//  com.acme.ios.photos
//
//  Created by Kevin LAUNAY on 27/10/2026.
//


import Foundation
import Network

public struct DiscoveredHost: Identifiable, Hashable, Sendable {
    public var id: String { "\(name)_\(resolvedHost ?? "")" }
    public let name: String        // e.g. "Kevin’s Mac mini"
    public var resolvedHost: String? // e.g. "192.168.1.50" or "macmini.local"
    public let endpoint: NWEndpoint
}
