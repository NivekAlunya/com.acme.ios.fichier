//
//  StubUptimeClock.swift
//  FichierTVTests
//
//

import Foundation

@MainActor
final class StubUptimeClock {
    var now: TimeInterval

    init(now: TimeInterval = 100.0) {
        self.now = now
    }
}
