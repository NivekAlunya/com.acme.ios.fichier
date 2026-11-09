//
//  StubNowPlayingSnapshot.swift
//  FichierTVTests
//
//

import Foundation

struct StubNowPlayingSnapshot: Equatable, Sendable {
    let title: String
    let currentTime: Double
    let duration: Double
    let isPlaying: Bool
}
