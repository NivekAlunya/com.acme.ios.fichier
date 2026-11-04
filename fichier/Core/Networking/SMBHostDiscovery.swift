//
//  SMBHostDiscovery.swift
//  fichier
//

import Foundation
import Network
import Observation
import OSLog

/// A network service discovery coordinator that locates SMB servers on the local area network using Bonjour (mDNS).
///
/// ### Architecture & Concurrency Overview
/// - **Actor Isolation**: `@Observable @MainActor public final class`, ensuring all property updates (`discoveredHosts`, `isScanning`)
///   dispatch synchronously to SwiftUI views on the main thread.
/// - **Network Framework**: Leverages Apple's modern `Network.framework` (`NWBrowser`, `NWConnection`) rather than legacy `NSNetService`.
/// - **IPv4 Resolution**: Forces IPv4 address extraction because low-level SMB2 client libraries require dot-decimal IPv4
///   or clean hostnames to negotiate TCP connections without scope ID `%interface` suffix complications.
@Observable
@MainActor
public final class SMBHostDiscovery {
    
    // MARK: - Observable State
    
    /// The sorted list of discovered SMB hosts on the local network.
    public var discoveredHosts: [DiscoveredHost] = []
    
    /// Indicates whether the Bonjour browser is actively listening for network advertisements.
    public var isScanning = false
    
    /// User-facing error message populated if Bonjour browsing or socket creation fails.
    public var errorMessage: String?
    
    // MARK: - Private State
    
    /// Active `NWBrowser` instance executing local multicast DNS queries.
    private var browser: NWBrowser?
    
    /// Ephemeral `NWConnection` instances currently resolving Bonjour service endpoints to numeric IP addresses.
    private var pendingConnections: [NWConnection] = []
    
    // MARK: - Initialization
    
    /// Creates a new host discovery coordinator in an idle state.
    public init() {}
    
    // MARK: - Discovery Lifecycle
    
    /// Begins scanning the local network for SMB services (`_smb._tcp`).
    ///
    /// ### Complex Code Breakdown:
    /// - **Protocol Configuration**: Sets `NWParameters.includePeerToPeer = true` to discover local Wi-Fi Direct and AWDL peers.
    ///   Restricts IP protocol options to IPv4 (`ipOptions.version = .v4`) to avoid unreachable link-local IPv6 addresses.
    /// - **Service Descriptor**: Targets Bonjour service type `_smb._tcp` in domain `local.`.
    /// - **Handler Dispatching**: Browser callbacks are bridged back to the `@MainActor` via `Task { @MainActor in }`.
    public func startDiscovery() {
        stopDiscovery()
        discoveredHosts = []
        isScanning = true
        errorMessage = nil
        
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        if let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }
        
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_smb._tcp", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: parameters)
        self.browser = browser
        
        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    AppLog.discovery.info("SMB browser is active and scanning (IPv4)")
                case .failed(let error):
                    AppLog.discovery.error("Scan failed: \(error.localizedDescription)")
                    self.errorMessage = String(localized: .Strings.networkingErrorDiscoveryFailed(error.localizedDescription))
                    self.isScanning = false
                case .cancelled:
                    self.isScanning = false
                default:
                    break
                }
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleBrowseResults(results)
            }
        }
        
        browser.start(queue: .main)
    }
    
    /// Stops the active Bonjour scan and cancels all in-flight endpoint resolution sockets.
    public func stopDiscovery() {
        browser?.cancel()
        browser = nil
        for conn in pendingConnections {
            conn.cancel()
        }
        pendingConnections.removeAll()
        isScanning = false
    }
    
    // MARK: - Browse Result Processing
    
    /// Processes newly delivered Bonjour discovery results, updates the host list, and triggers IPv4 resolution.
    ///
    /// - Parameter results: The current snapshot set of `NWBrowser.Result` entries reported by the network stack.
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var hosts: [DiscoveredHost] = []
        
        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                AppLog.discovery.debug("Found SMB host: \(name, privacy: .private)")
                let host = DiscoveredHost(name: name, endpoint: result.endpoint)
                hosts.append(host)
                
                // Asynchronously resolve strictly to IPv4
                resolveIPv4Host(for: host)
            }
        }
        
        self.discoveredHosts = hosts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - IPv4 Address Resolution
    
    /// Spawns a lightweight `NWConnection` to resolve a Bonjour service endpoint into a clean IPv4 address or hostname.
    ///
    /// ### Complex Code Breakdown:
    /// - **Endpoint Probing**: Bonjour advertisements provide service names (e.g. `MacMini._smb._tcp.local.`),
    ///   not direct IP addresses. Initiating a temporary TCP connection forces the system resolver to establish routing.
    /// - **Scope ID Truncation**: When resolving link-local or Wi-Fi endpoints, raw IPv4 strings might contain interface
    ///   suffixes (e.g. `192.168.1.50%en0`). The code strips `%...` to prevent URL parser failures in AMSMB2.
    /// - **Immediate Teardown**: As soon as `connection.currentPath?.remoteEndpoint` resolves the remote host,
    ///   the connection is cancelled and purged from `pendingConnections`.
    ///
    /// - Parameter host: The `DiscoveredHost` to resolve.
    private func resolveIPv4Host(for host: DiscoveredHost) {
        let tcpParams = NWParameters.tcp
        if let ipOptions = tcpParams.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4 // Force IPv4 resolution only
        }
        
        let connection = NWConnection(to: host.endpoint, using: tcpParams)
        pendingConnections.append(connection)
        
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                switch state {
                case .ready:
                    if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                       case let .hostPort(resolvedHost, _) = innerEndpoint {
                        
                        var ipv4String: String?
                        switch resolvedHost {
                        case .ipv4(let ip):
                            // Strip any interface suffix like %en0
                            let raw = "\(ip)"
                            ipv4String = raw.components(separatedBy: "%").first ?? raw
                        case .name(let name, _):
                            ipv4String = name
                        case .ipv6:
                            // Ignore IPv6 addresses
                            break
                        @unknown default:
                            break
                        }
                        
                        if let validHost = ipv4String {
                            AppLog.discovery.debug("Resolved \(host.name, privacy: .private) -> IPv4: \(validHost, privacy: .private)")
                            self.updateResolvedHost(for: host.name, resolvedHost: validHost)
                        }
                    }
                    self.pendingConnections.removeAll { $0 === connection }
                    connection.cancel()
                case .failed, .cancelled:
                    self.pendingConnections.removeAll { $0 === connection }
                    connection.cancel()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }
    
    /// Updates an existing entry in `discoveredHosts` with its newly resolved IPv4 hostname or IP address.
    ///
    /// - Parameters:
    ///   - name: The Bonjour service name.
    ///   - resolvedHost: The resolved IPv4 string or clean hostname.
    private func updateResolvedHost(for name: String, resolvedHost: String) {
        if let idx = discoveredHosts.firstIndex(where: { $0.name == name }) {
            discoveredHosts[idx].resolvedHost = resolvedHost
        }
    }
}
