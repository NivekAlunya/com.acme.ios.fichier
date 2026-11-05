//
//  VideoTrackManagerTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest

@MainActor
final class VideoTrackManagerTests: XCTestCase {
    func testInitialState() {
        let manager = VideoTrackManager()
        XCTAssertTrue(manager.availableAudios.isEmpty)
        XCTAssertNil(manager.selectedAudioID)
        XCTAssertTrue(manager.availableSubtitles.isEmpty)
        XCTAssertNil(manager.selectedSubtitleID)
        XCTAssertFalse(manager.isSubtitlesEnabled)
        XCTAssertFalse(manager.hasOptions)
        XCTAssertEqual(manager.playbackRate, .normal)
    }
    
    func testResetClearsState() {
        let manager = VideoTrackManager()
        let dummyURL = URL(fileURLWithPath: "/dev/null")
        let engine = ExtendedPlayerEngine(url: dummyURL)
        
        manager.loadTracks(for: engine)
        manager.reset()
        
        XCTAssertTrue(manager.availableAudios.isEmpty)
        XCTAssertNil(manager.selectedAudioID)
        XCTAssertTrue(manager.availableSubtitles.isEmpty)
        XCTAssertNil(manager.selectedSubtitleID)
        XCTAssertFalse(manager.isSubtitlesEnabled)
    }
    
    func testSelectAudioUpdatesSelection() {
        let manager = VideoTrackManager()
        let dummyURL = URL(fileURLWithPath: "/dev/null")
        let engine = ExtendedPlayerEngine(url: dummyURL)
        
        let option = VideoTrackOption(id: "vlc_audio_1_English", displayName: "English", vlcTrackIndex: 1)
        manager.selectAudio(option: option, engine: engine)
        
        XCTAssertEqual(manager.selectedAudioID, "vlc_audio_1_English")
        XCTAssertEqual(engine.currentAudioTrackIndex, 1)
    }
    
    func testSelectSubtitleUpdatesSelection() {
        let manager = VideoTrackManager()
        let dummyURL = URL(fileURLWithPath: "/dev/null")
        let engine = ExtendedPlayerEngine(url: dummyURL)
        
        let subOption = VideoTrackOption(id: "vlc_sub_2_French", displayName: "French", vlcTrackIndex: 2)
        manager.selectSubtitle(option: subOption, engine: engine)
        
        XCTAssertEqual(manager.selectedSubtitleID, "vlc_sub_2_French")
        XCTAssertTrue(manager.isSubtitlesEnabled)
        XCTAssertEqual(engine.currentSubtitleTrackIndex, 2)
        
        let offOption = VideoTrackOption(id: "sub_off", displayName: "Off", vlcTrackIndex: -1)
        manager.selectSubtitle(option: offOption, engine: engine)
        
        XCTAssertEqual(manager.selectedSubtitleID, "sub_off")
        XCTAssertFalse(manager.isSubtitlesEnabled)
        XCTAssertEqual(engine.currentSubtitleTrackIndex, -1)
    }
}
#endif
