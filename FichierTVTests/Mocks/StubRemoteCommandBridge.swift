//
//  StubRemoteCommandBridge.swift
//  FichierTVTests
//
//

import Foundation
@testable import FichierTV

@MainActor
final class StubRemoteCommandBridge: TVRemoteCommandHandling {
    private(set) var activateCount: Int = 0
    private(set) var deactivateCount: Int = 0
    private(set) var nowPlayingUpdates: [StubNowPlayingSnapshot] = []
    private(set) var activeCallbacks: TVRemoteCommandCallbacks?

    func activate(callbacks: TVRemoteCommandCallbacks) {
        activateCount += 1
        activeCallbacks = callbacks
    }

    func updateNowPlaying(title: String, currentTime: Double, duration: Double, isPlaying: Bool) {
        nowPlayingUpdates.append(
            StubNowPlayingSnapshot(
                title: title,
                currentTime: currentTime,
                duration: duration,
                isPlaying: isPlaying
            )
        )
    }

    func deactivate() {
        deactivateCount += 1
        activeCallbacks = nil
    }

    func simulateSeekBegan(isForward: Bool, timestamp: TimeInterval) {
        activeCallbacks?.onSeekBegan(isForward, timestamp)
    }

    func simulateSeekEnded(isForward: Bool, timestamp: TimeInterval) {
        activeCallbacks?.onSeekEnded(isForward, timestamp)
    }

    func simulateTapSkip(isForward: Bool, timestamp: TimeInterval) {
        activeCallbacks?.onTapSkip(isForward, timestamp)
    }

    func simulatePlay() {
        activeCallbacks?.onPlay()
    }

    func simulatePause() {
        activeCallbacks?.onPause()
    }

    func simulateTogglePlayPause(timestamp: TimeInterval) {
        activeCallbacks?.onTogglePlayPause(timestamp)
    }
}
