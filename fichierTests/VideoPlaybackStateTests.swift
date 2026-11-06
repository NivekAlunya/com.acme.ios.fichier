//
//  VideoPlaybackStateTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
@testable import fichier

@MainActor
final class VideoPlaybackStateTests: XCTestCase {
    func testPlaybackStateEquality() {
        let testItem = MediaItem(
            locationID: "loc1",
            name: "test.mp4",
            rootName: "media",
            path: "videos/test.mp4",
            isDirectory: false
        )
        
        XCTAssertEqual(VideoPlaybackState.idle, VideoPlaybackState.idle)
        XCTAssertEqual(VideoPlaybackState.buffering, VideoPlaybackState.buffering)
        XCTAssertEqual(VideoPlaybackState.playing, VideoPlaybackState.playing)
        XCTAssertEqual(VideoPlaybackState.paused, VideoPlaybackState.paused)
        XCTAssertEqual(VideoPlaybackState.loading(testItem), VideoPlaybackState.loading(testItem))
        XCTAssertEqual(VideoPlaybackState.failed("error"), VideoPlaybackState.failed("error"))
        
        XCTAssertNotEqual(VideoPlaybackState.idle, VideoPlaybackState.playing)
        XCTAssertNotEqual(VideoPlaybackState.failed("error 1"), VideoPlaybackState.failed("error 2"))
    }
    
    func testIsPlayingProperty() {
        XCTAssertTrue(VideoPlaybackState.playing.isPlaying)
        XCTAssertFalse(VideoPlaybackState.idle.isPlaying)
        XCTAssertFalse(VideoPlaybackState.buffering.isPlaying)
        XCTAssertFalse(VideoPlaybackState.paused.isPlaying)
        XCTAssertFalse(VideoPlaybackState.failed("error").isPlaying)
    }
    
    func testIsBufferingProperty() {
        let testItem = MediaItem(
            locationID: "loc1",
            name: "test.mp4",
            rootName: "media",
            path: "videos/test.mp4",
            isDirectory: false
        )
        
        XCTAssertTrue(VideoPlaybackState.buffering.isBuffering)
        XCTAssertTrue(VideoPlaybackState.loading(testItem).isBuffering)
        
        XCTAssertFalse(VideoPlaybackState.idle.isBuffering)
        XCTAssertFalse(VideoPlaybackState.playing.isBuffering)
        XCTAssertFalse(VideoPlaybackState.paused.isBuffering)
        XCTAssertFalse(VideoPlaybackState.failed("error").isBuffering)
    }
    
    func testStateTransitionsSimulation() {
        let testItem = MediaItem(
            locationID: "loc1",
            name: "test.mp4",
            rootName: "media",
            path: "videos/test.mp4",
            isDirectory: false
        )
        
        var state: VideoPlaybackState = .idle
        XCTAssertEqual(state, .idle)
        
        state = .loading(testItem)
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
