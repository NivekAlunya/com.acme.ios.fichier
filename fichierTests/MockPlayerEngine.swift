//
//  MockPlayerEngine.swift
//  fichierTests
//
//  Created for testing PlayerEngine integrations.
//

#if DEBUG
import Foundation
import FichierKit
@testable import fichier

@MainActor
final class MockPlayerEngine: PlayerEngine {
    var playbackState: PlayerPlaybackState = .idle
    var isPlaying: Bool { playbackState == .playing }
    var currentTime: Double = 0
    var duration: Double = 0
    var volume: Double = 1.0
    var isMuted: Bool = false
    var playbackRate: Float = 1.0

    var availableAudioTracks: [PlayerAudioTrack] = []
    var selectedAudioTrack: PlayerAudioTrack?
    var availableSubtitleTracks: [PlayerSubtitleTrack] = []
    var selectedSubtitleTrack: PlayerSubtitleTrack?
    var availableChapters: [PlayerChapter] = []

    private(set) var playCount: Int = 0
    private(set) var pauseCount: Int = 0
    private(set) var seekCalls: [(seconds: Double, toleranceBefore: Double, toleranceAfter: Double)] = []

    func play() {
        playCount += 1
        playbackState = .playing
    }

    func pause() {
        pauseCount += 1
        playbackState = .paused
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to seconds: Double) {
        currentTime = seconds
    }

    func seek(to seconds: Double, precision: PlayerSeekPrecision) {
        currentTime = seconds
    }

    func seek(
        to seconds: Double,
        toleranceBefore: Double,
        toleranceAfter: Double,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        currentTime = seconds
        seekCalls.append((seconds: seconds, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter))
        completion?(true)
    }

    func next() {}
    func previous() {}

    func selectAudioTrack(_ track: PlayerAudioTrack) {
        selectedAudioTrack = track
    }

    func selectSubtitleTrack(_ track: PlayerSubtitleTrack?) {
        selectedSubtitleTrack = track
    }

    func tearDown() {
        playbackState = .idle
    }
}
#endif
