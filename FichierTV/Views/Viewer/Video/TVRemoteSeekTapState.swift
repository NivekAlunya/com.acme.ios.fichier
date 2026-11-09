//
//  TVRemoteSeekTapState.swift
//  FichierTV
//
//

import Foundation

/// Tracks the most recent short tap commit to support double-tap acceleration within 0.5s.
struct TVRemoteSeekTapState: Equatable, Sendable {
    let isForward: Bool
    let releaseTimestamp: TimeInterval
    let originTime: Double
    let committedTargetTime: Double
    let tapCountInPair: Int
}
