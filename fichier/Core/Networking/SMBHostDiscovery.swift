//
//  SMBHostDiscovery.swift
//  com.acme.ios.photos
//
//  Created by Kevin LAUNAY on 27/10/2026.
//

import Foundation
import Network
import Observation

@Observable
@MainActor
public final class SMBHostDiscovery {
    public var discoveredHosts: [DiscoveredHost] = []
    public var isScanning = false
    public var errorMessage: String?
    
    private var browser: NWBrowser?
    
    public init() {}
    
    public func startDiscovery() {
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
            Task { @MainActor in
                switch state {
                case .ready:
                    print("📡 [Bonjour] SMB Browser is active and scanning (IPv4)...")
                case .failed(let error):
                    print("❌ [Bonjour] Scan failed: \(error)")
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
            Task { @MainActor in
                self.handleBrowseResults(results)
            }
        }
        
        browser.start(queue: .main)
    }
    
    public func stopDiscovery() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var hosts: [DiscoveredHost] = []
        
        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                print("💻 [Bonjour] Found SMB Host: \(name)")
                let host = DiscoveredHost(name: name, endpoint: result.endpoint)
                hosts.append(host)
                
                // Asynchronously resolve strictly to IPv4
                resolveIPv4Host(for: host)
            }
        }
        
        self.discoveredHosts = hosts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    /// Resolves Bonjour service endpoint strictly to an IPv4 address (e.g. 192.168.1.x)
    private func resolveIPv4Host(for host: DiscoveredHost) {
        let tcpParams = NWParameters.tcp
        if let ipOptions = tcpParams.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4 // 👈 Force IPv4 resolution only
        }
        
        let connection = NWConnection(to: host.endpoint, using: tcpParams)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let innerEndpoint = connection?.currentPath?.remoteEndpoint,
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
                        // Ignore IPv6
                        break
                    @unknown default:
                        break
                    }
                    
                    if let validHost = ipv4String {
                        print("✅ [Bonjour] Resolved \(host.name) -> IPv4: \(validHost)")
                        Task { @MainActor in
                            self.updateResolvedHost(for: host.name, resolvedHost: validHost)
                        }
                    }
                }
                connection?.cancel()
            case .failed, .cancelled:
                connection?.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global())
    }
    
    private func updateResolvedHost(for name: String, resolvedHost: String) {
        if let idx = discoveredHosts.firstIndex(where: { $0.name == name }) {
            discoveredHosts[idx].resolvedHost = resolvedHost
        }
    }
}
