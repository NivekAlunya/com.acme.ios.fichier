//
//  VideoTrackManagerTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
import FichierKit
@testable import fichier

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
        let engine = TVVLCPlayerEngine()
        engine.load(url: dummyURL)
        
        manager.loadTracks(for: engine)
        manager.reset()
        
        XCTAssertTrue(manager.availableAudios.isEmpty)
        XCTAssertNil(manager.selectedAudioID)
        XCTAssertTrue(manager.availableSubtitles.isEmpty)
        XCTAssertNil(manager.selectedSubtitleID)
        XCTAssertFalse(manager.isSubtitlesEnabled)
    }
    
    func testLoadTracksPrependsOffOptionAndMapsAudioAndSubtitles() {
        let manager = VideoTrackManager()
        let engine = MockPlayerEngine()
        let audio0 = PlayerAudioTrack(id: "aud_0", title: "English")
        let audio1 = PlayerAudioTrack(id: "aud_1", title: "French")
        let sub0 = PlayerSubtitleTrack(id: "sub_0", title: "English SDH")
        engine.availableAudioTracks = [audio0, audio1]
        engine.selectedAudioTrack = audio1
        engine.availableSubtitleTracks = [sub0]
        engine.selectedSubtitleTrack = nil

        manager.loadTracks(for: engine)

        XCTAssertEqual(manager.availableAudios.map(\.id), ["aud_0", "aud_1"])
        XCTAssertEqual(manager.selectedAudioID, "aud_1")
        XCTAssertEqual(manager.availableSubtitles.map(\.id), ["sub_off", "sub_0"])
        XCTAssertEqual(manager.selectedSubtitleID, "sub_off")
        XCTAssertFalse(manager.isSubtitlesEnabled)
        XCTAssertTrue(manager.hasOptions)
    }

    func testSelectAudioUpdatesSelection() {
        let manager = VideoTrackManager()
        let engine = MockPlayerEngine()
        let audio = PlayerAudioTrack(id: "vlc_audio_1_English", title: "English", languageCode: "en")
        let option = VideoTrackOption(id: audio.id, displayName: audio.title, playerAudioTrack: audio)
        
        manager.selectAudio(option: option, engine: engine)
        
        XCTAssertEqual(manager.selectedAudioID, audio.id)
        XCTAssertEqual(engine.selectedAudioTrack, audio)
    }
    
    func testSelectAndToggleSubtitleUpdatesSelection() {
        let manager = VideoTrackManager()
        let engine = MockPlayerEngine()
        let subtitle = PlayerSubtitleTrack(id: "vlc_sub_2_French", title: "French", languageCode: "fr")
        engine.availableSubtitleTracks = [subtitle]
        manager.loadTracks(for: engine)
        
        let subOption = VideoTrackOption(id: subtitle.id, displayName: subtitle.title, playerSubtitleTrack: subtitle)
        manager.selectSubtitle(option: subOption, engine: engine)
        
        XCTAssertEqual(manager.selectedSubtitleID, subtitle.id)
        XCTAssertTrue(manager.isSubtitlesEnabled)
        XCTAssertEqual(engine.selectedSubtitleTrack, subtitle)
        
        let offOption = VideoTrackOption(id: "sub_off", displayName: "Off", playerSubtitleTrack: nil)
        manager.selectSubtitle(option: offOption, engine: engine)
        
        XCTAssertEqual(manager.selectedSubtitleID, "sub_off")
        XCTAssertFalse(manager.isSubtitlesEnabled)
        XCTAssertNil(engine.selectedSubtitleTrack)
        
        manager.toggleSubtitles(engine: engine)
        XCTAssertEqual(manager.selectedSubtitleID, subtitle.id)
        XCTAssertTrue(manager.isSubtitlesEnabled)
        XCTAssertEqual(engine.selectedSubtitleTrack, subtitle)
    }
    
    func testSetPlaybackRateUpdatesEngine() {
        let manager = VideoTrackManager()
        let engine = MockPlayerEngine()
        
        manager.setPlaybackRate(.speed1_5, for: engine)
        
        XCTAssertEqual(manager.playbackRate, .speed1_5)
        XCTAssertEqual(engine.playbackRate, 1.5, accuracy: 0.001)
    }
}
#endif
