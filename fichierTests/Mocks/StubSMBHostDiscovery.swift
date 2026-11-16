//
//  StubSMBHostDiscovery.swift
//  fichierTests
//

import Foundation
import Observation
import FichierKit

@Observable
@MainActor
final class StubSMBHostDiscovery: SMBHostDiscoveryProtocol {
    var discoveredHosts: [DiscoveredHost]
    var isScanning = false
    var errorMessage: String?

    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(discoveredHosts: [DiscoveredHost] = [], errorMessage: String? = nil) {
        self.discoveredHosts = discoveredHosts
        self.errorMessage = errorMessage
    }

    func startDiscovery() {
        startCount += 1
        isScanning = true
    }

    func stopDiscovery() {
        stopCount += 1
        isScanning = false
    }
}
