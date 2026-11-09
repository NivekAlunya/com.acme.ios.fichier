//
//  StubVideoPlaybackStore.swift
//  FichierTVTests
//
//

import Foundation
import FichierKit

actor StubVideoPlaybackStore: VideoPlaybackStoreProtocol {
    private var positions: [String: Double] = [:]

    init(initialPositions: [String: Double] = [:]) {
        self.positions = initialPositions
    }

    func savePlaybackPosition(itemID: String, time: Double, duration: Double) async {
        if duration > 0 && (duration - time) < 15.0 {
            positions.removeValue(forKey: itemID)
            return
        }
        guard time >= 10.0 else { return }
        positions[itemID] = time
    }

    func playbackPosition(for itemID: String) async -> Double? {
        positions[itemID]
    }

    func clearPlaybackPosition(for itemID: String) async {
        positions.removeValue(forKey: itemID)
    }
}
