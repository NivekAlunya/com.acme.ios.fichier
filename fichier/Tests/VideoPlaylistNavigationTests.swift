//
//  VideoPlaylistNavigationTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
@testable import fichier

@MainActor
final class VideoPlaylistNavigationTests: XCTestCase {
    
    private func createTestMediaItem(name: String) -> MediaItem {
        MediaItem(
            locationID: "loc_test",
            name: name,
            rootName: "videos",
            path: "videos/\(name)",
            isDirectory: false
        )
    }
    
    func testSingleVideoPlaylistNavigation() {
        let manager = StorageLocationManager()
        let item1 = createTestMediaItem(name: "clip1.mp4")
        
        let controller = VideoPlayerController(
            manager: manager,
            videos: [item1],
            initialItem: item1
        )
        
        XCTAssertEqual(controller.videos.count, 1)
        XCTAssertEqual(controller.currentIndex, 0)
        XCTAssertEqual(controller.currentItem.id, item1.id)
        
        // Next & Previous on single video should remain on item1
        controller.goToNext()
        XCTAssertEqual(controller.currentIndex, 0)
        
        controller.goToPrevious()
        XCTAssertEqual(controller.currentIndex, 0)
    }
    
    func testMultipleVideosPlaylistNavigation() {
        let manager = StorageLocationManager()
        let item1 = createTestMediaItem(name: "clip1.mp4")
        let item2 = createTestMediaItem(name: "clip2.mp4")
        let item3 = createTestMediaItem(name: "clip3.mp4")
        let playlist = [item1, item2, item3]
        
        let controller = VideoPlayerController(
            manager: manager,
            videos: playlist,
            initialItem: item1
        )
        
        XCTAssertEqual(controller.videos.count, 3)
        XCTAssertEqual(controller.currentIndex, 0)
        
        // Advance to next video
        controller.goToNext()
        XCTAssertEqual(controller.currentIndex, 1)
        XCTAssertEqual(controller.currentItem.id, item2.id)
        
        controller.goToNext()
        XCTAssertEqual(controller.currentIndex, 2)
        XCTAssertEqual(controller.currentItem.id, item3.id)
        
        // Wrap around to start
        controller.goToNext()
        XCTAssertEqual(controller.currentIndex, 0)
        XCTAssertEqual(controller.currentItem.id, item1.id)
        
        // Backward navigation with wrap around to last item
        controller.goToPrevious()
        XCTAssertEqual(controller.currentIndex, 2)
        XCTAssertEqual(controller.currentItem.id, item3.id)
        
        controller.goToPrevious()
        XCTAssertEqual(controller.currentIndex, 1)
        XCTAssertEqual(controller.currentItem.id, item2.id)
    }
    
    func testPlayNextVideoAdvancesLinearlyUntilEnd() {
        let manager = StorageLocationManager()
        let item1 = createTestMediaItem(name: "clip1.mp4")
        let item2 = createTestMediaItem(name: "clip2.mp4")
        let playlist = [item1, item2]
        
        let controller = VideoPlayerController(
            manager: manager,
            videos: playlist,
            initialItem: item1
        )
        
        XCTAssertEqual(controller.currentIndex, 0)
        
        // Play next advances to item2
        controller.playNextVideo()
        XCTAssertEqual(controller.currentIndex, 1)
        XCTAssertEqual(controller.currentItem.id, item2.id)
        
        // At end of playlist, playNextVideo does not wrap (reveals controls instead and pauses)
        controller.playNextVideo()
        XCTAssertEqual(controller.currentIndex, 1)
        XCTAssertTrue(controller.showControls)
        XCTAssertEqual(controller.playbackState, .paused)
    }
    
    func testIsAtEndCalculation() {
        let manager = StorageLocationManager()
        let item1 = createTestMediaItem(name: "clip1.mp4")
        
        let controller = VideoPlayerController(
            manager: manager,
            videos: [item1],
            initialItem: item1
        )
        
        controller.totalDurationSeconds = 60.0
        controller.currentPlaybackSeconds = 30.0
        controller.playbackState = .paused
        XCTAssertFalse(controller.isAtEnd)
        
        // When nearing duration within 0.5s while paused
        controller.currentPlaybackSeconds = 59.8
        XCTAssertTrue(controller.isAtEnd)
        
        // If actively playing, isAtEnd is false
        controller.playbackState = .playing
        XCTAssertFalse(controller.isAtEnd)
    }
    
    func testSeekRelativeFifteenSeconds() {
        let manager = StorageLocationManager()
        let item1 = createTestMediaItem(name: "clip1.mp4")
        
        let controller = VideoPlayerController(
            manager: manager,
            videos: [item1],
            initialItem: item1
        )
        
        controller.totalDurationSeconds = 60.0
        controller.currentPlaybackSeconds = 30.0
        controller.playbackState = .paused
        
        // Seek backward 15s
        controller.seekRelative(-15)
        XCTAssertEqual(controller.currentPlaybackSeconds, 15.0, accuracy: 0.001)
        XCTAssertTrue(controller.showControls)
        
        // Seek forward 15s
        controller.seekRelative(15)
        XCTAssertEqual(controller.currentPlaybackSeconds, 30.0, accuracy: 0.001)
        XCTAssertTrue(controller.showControls)
        
        // Backward clamp at 0
        controller.currentPlaybackSeconds = 5.0
        controller.seekRelative(-15)
        XCTAssertEqual(controller.currentPlaybackSeconds, 0.0, accuracy: 0.001)
        
        // Forward clamp at totalDuration
        controller.currentPlaybackSeconds = 55.0
        controller.seekRelative(15)
        XCTAssertEqual(controller.currentPlaybackSeconds, 60.0, accuracy: 0.001)
    }
    
    func testTogglePlayPauseWhenAtEndReplaysFromStart() {
        let manager = StorageLocationManager()
        let item1 = createTestMediaItem(name: "clip1.mp4")
        
        let controller = VideoPlayerController(
            manager: manager,
            videos: [item1],
            initialItem: item1
        )
        
        controller.totalDurationSeconds = 60.0
        controller.currentPlaybackSeconds = 59.8
        controller.playbackState = .paused
        XCTAssertTrue(controller.isAtEnd)
        
        controller.togglePlayPause()
        XCTAssertEqual(controller.currentPlaybackSeconds, 0.0, accuracy: 0.001)
    }
}
#endif
