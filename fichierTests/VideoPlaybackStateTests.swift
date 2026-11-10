//
//  VideoPlaybackStateTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
import FichierKit
@testable import fichier

@MainActor
final class VideoPlaybackStateTests: XCTestCase {
    func testPlaybackStateEquality() {
        XCTAssertEqual(PlayerPlaybackState.idle, PlayerPlaybackState.idle)
        XCTAssertEqual(PlayerPlaybackState.buffering, PlayerPlaybackState.buffering)
        XCTAssertEqual(PlayerPlaybackState.playing, PlayerPlaybackState.playing)
        XCTAssertEqual(PlayerPlaybackState.paused, PlayerPlaybackState.paused)
        XCTAssertEqual(PlayerPlaybackState.loading, PlayerPlaybackState.loading)
        XCTAssertEqual(PlayerPlaybackState.failed("error"), PlayerPlaybackState.failed("error"))
        
        XCTAssertNotEqual(PlayerPlaybackState.idle, PlayerPlaybackState.playing)
        XCTAssertNotEqual(PlayerPlaybackState.failed("error 1"), PlayerPlaybackState.failed("error 2"))
    }
    
    func testIsPlayingProperty() {
        XCTAssertTrue(PlayerPlaybackState.playing.isPlaying)
        XCTAssertFalse(PlayerPlaybackState.idle.isPlaying)
        XCTAssertFalse(PlayerPlaybackState.loading.isPlaying)
        XCTAssertFalse(PlayerPlaybackState.buffering.isPlaying)
        XCTAssertFalse(PlayerPlaybackState.paused.isPlaying)
        XCTAssertFalse(PlayerPlaybackState.failed("error").isPlaying)
    }
    
    func testIsBufferingProperty() {
        XCTAssertTrue(PlayerPlaybackState.buffering.isBuffering)
        XCTAssertTrue(PlayerPlaybackState.loading.isBuffering)
        
        XCTAssertFalse(PlayerPlaybackState.idle.isBuffering)
        XCTAssertFalse(PlayerPlaybackState.playing.isBuffering)
        XCTAssertFalse(PlayerPlaybackState.paused.isBuffering)
        XCTAssertFalse(PlayerPlaybackState.failed("error").isBuffering)
    }
    
    func testStateTransitionsSimulation() {
        var state: PlayerPlaybackState = .idle
        XCTAssertEqual(state, .idle)
        
        state = .loading
        XCTAssertTrue(state.isBuffering)
        XCTAssertFalse(state.isPlaying)
        
        state = .buffering
        XCTAssertTrue(state.isBuffering)
        XCTAssertFalse(state.isPlaying)
        
        state = .playing
        XCTAssertFalse(state.isBuffering)
        XCTAssertTrue(state.isPlaying)
        
        state = .paused
        XCTAssertFalse(state.isBuffering)
        XCTAssertFalse(state.isPlaying)
        
        state = .failed("Connection lost")
        XCTAssertFalse(state.isBuffering)
        XCTAssertFalse(state.isPlaying)
        if case .failed(let message) = state {
            XCTAssertEqual(message, "Connection lost")
        } else {
            XCTFail("Expected .failed state")
        }
    }
}
#endif
