//
//  VideoSeekCoordinatorTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
import CoreMedia

@MainActor
final class VideoSeekCoordinatorTests: XCTestCase {
    func testInitialState() {
        let coordinator = VideoSeekCoordinator()
        XCTAssertFalse(coordinator.isScrubbingTimeline)
        XCTAssertFalse(coordinator.isScrubbingWithGesture)
        XCTAssertFalse(coordinator.isScrubbing)
        XCTAssertFalse(coordinator.isSeekingFrame)
        XCTAssertFalse(coordinator.isFinishingSeek)
        XCTAssertEqual(coordinator.seekGeneration, 0)
        XCTAssertNil(coordinator.pendingSeekSeconds)
    }
    
    func testTimelineScrubbingLifecycle() {
        let coordinator = VideoSeekCoordinator()
        
        coordinator.startTimelineScrubbing(currentPlaybackSeconds: 42.0, isPlaying: false, player: nil)
        XCTAssertTrue(coordinator.isScrubbingTimeline)
        XCTAssertTrue(coordinator.isScrubbing)
        XCTAssertEqual(coordinator.lastSeekTargetSeconds, 42.0)
        XCTAssertFalse(coordinator.wasPlayingBeforeScrub)
        
        coordinator.endTimelineScrubbing()
        XCTAssertFalse(coordinator.isScrubbingTimeline)
        XCTAssertFalse(coordinator.isScrubbing)
    }
    
    func testTimelineScrubbingWithEngine() {
        let coordinator = VideoSeekCoordinator()
        coordinator.startTimelineScrubbing(currentPlaybackSeconds: 30.0, isPlaying: true, engine: nil)
        XCTAssertTrue(coordinator.isScrubbingTimeline)
        XCTAssertTrue(coordinator.isScrubbing)
        XCTAssertTrue(coordinator.wasPlayingBeforeScrub)
        coordinator.endTimelineScrubbing()
        XCTAssertFalse(coordinator.isScrubbing)
    }
    
    func testGestureScrubbingLifecycle() {
        let coordinator = VideoSeekCoordinator()
        
        coordinator.startGestureScrubbing(currentPlaybackSeconds: 15.5, isPlaying: true, player: nil)
        XCTAssertTrue(coordinator.isScrubbingWithGesture)
        XCTAssertTrue(coordinator.isScrubbing)
        XCTAssertEqual(coordinator.initialScrubTime, 15.5)
        XCTAssertEqual(coordinator.lastSeekTargetSeconds, 15.5)
        XCTAssertTrue(coordinator.wasPlayingBeforeScrub)
        
        coordinator.endGestureScrubbing()
        XCTAssertFalse(coordinator.isScrubbingWithGesture)
        XCTAssertFalse(coordinator.isScrubbing)
    }
    
    func testLiveSeekToleranceBuckets() {
        let coordinator = VideoSeekCoordinator()
        coordinator.lastSeekTargetSeconds = 10.0
        
        // Sub-second jump (< 1.0s delta): fine tolerance (0.5s)
        let fineTolerance = coordinator.liveSeekTolerance(for: 10.4)
        XCTAssertEqual(fineTolerance.seconds, 0.5)
        
        // Mid-range jump (1.0..<5.0s delta): medium tolerance (1.5s)
        let midTolerance = coordinator.liveSeekTolerance(for: 13.0)
        XCTAssertEqual(midTolerance.seconds, 1.5)
        
        // Large jump (>= 5.0s delta): positiveInfinity tolerance
        let coarseTolerance = coordinator.liveSeekTolerance(for: 25.0)
        XCTAssertTrue(coarseTolerance.isPositiveInfinity)
    }
    
    func testResetIncrementsGenerationAndClearsState() {
        let coordinator = VideoSeekCoordinator()
        coordinator.startTimelineScrubbing(currentPlaybackSeconds: 10, isPlaying: false, player: nil)
        XCTAssertTrue(coordinator.isScrubbing)
        
        let prevGeneration = coordinator.seekGeneration
        coordinator.reset()
        
        XCTAssertFalse(coordinator.isScrubbingTimeline)
        XCTAssertFalse(coordinator.isScrubbingWithGesture)
        XCTAssertFalse(coordinator.isScrubbing)
        XCTAssertFalse(coordinator.isSeekingFrame)
        XCTAssertFalse(coordinator.isFinishingSeek)
        XCTAssertNil(coordinator.pendingSeekSeconds)
        XCTAssertEqual(coordinator.seekGeneration, prevGeneration + 1)
    }
}
#endif
