//
//  TVRemoteSeekHoldState.swift
//  FichierTV
//
//

import Foundation

/// Tracks an in-progress press-and-hold seek prior to release or cancellation.
struct TVRemoteSeekHoldState: Equatable, Sendable {
    let isForward: Bool
    let source: TVRemoteSeekSource
    let anchorTime: Double
    let startTimestamp: TimeInterval
    let wasCancelledByMenu: Bool

    func cancellingByMenu() -> TVRemoteSeekHoldState {
        TVRemoteSeekHoldState(
            isForward: isForward,
            source: source,
            anchorTime: anchorTime,
            startTimestamp: startTimestamp,
            wasCancelledByMenu: true
        )
    }
}
