//
//  TVVideoPlayerViewModelTests.swift
//  FichierTVTests
//
//

import Foundation
import SwiftUI
import Testing
@testable import FichierTV
import FichierKit

@Suite("TVVideoPlayerViewModel Tests")
struct TVVideoPlayerViewModelTests {
    @Test("Routes native and extended video extensions to the proper engine")
    @MainActor
    func testEngineRoutingByExtension() {
        let mp4 = MediaSourceItem(id: "v1", name: "movie.mp4", path: "movie.mp4", type: .video)
        let mkv = MediaSourceItem(id: "v2", name: "concert.mkv", path: "concert.mkv", type: .video)
        let phVideo = MediaSourceItem(
            id: "v3",
            name: "clip.mov",
            path: "clip.mov",
            type: .video,
            phAssetIdentifier: "PH_123"
        )

        let viewModel = TVVideoPlayerViewModel(
            initialItem: mp4,
            videos: [mp4, mkv, phVideo],
            playbackStore: StubVideoPlaybackStore(),
            resolver: StubMediaSourceResolver()
        )

        #expect(viewModel.preferredEngineKind(for: mp4) == .native)
        #expect(viewModel.preferredEngineKind(for: mkv) == .extended)
        #expect(viewModel.preferredEngineKind(for: phVideo) == .native)
    }

    @Test("Implements first-press overlay reveal, scrubbing acceleration, and Menu hierarchy")
    @MainActor
    func testRemoteControlAndMenuHierarchy() {
        let video1 = MediaSourceItem(
            id: "v1",
            name: "sample.mkv",
            path: "sample.mkv",
            type: .video,
            localURL: URL(fileURLWithPath: "/tmp/sample.mkv")
        )
        let video2 = MediaSourceItem(
            id: "v2",
            name: "sample2.mp4",
            path: "sample2.mp4",
            type: .video,
            localURL: URL(fileURLWithPath: "/tmp/sample2.mp4")
        )

        let viewModel = TVVideoPlayerViewModel(
            initialItem: video1,
            videos: [video1, video2],
            playbackStore: StubVideoPlaybackStore(),
            resolver: StubMediaSourceResolver()
        )

        #expect(!viewModel.showOverlay)

        // Step 1: First D-pad press reveals overlay without navigating
        viewModel.handleDirectionalInput(direction: .up)
        #expect(viewModel.showOverlay)
        #expect(viewModel.activeFocusRow == .buttons)

        // Move to scrubber row & perform scrubbing
        viewModel.handleDirectionalInput(direction: .up)
        #expect(viewModel.activeFocusRow == .progress)

        viewModel.handleDirectionalInput(direction: .right)
        #expect(viewModel.isScrubbing)
        #expect(viewModel.scrubbingTime == 10.0)

        // Step 1 of Menu hierarchy: cancel scrubbing first, overlay remains visible
        #expect(viewModel.handleMenuPress())
        #expect(!viewModel.isScrubbing)
        #expect(viewModel.scrubbingTime == nil)
        #expect(viewModel.showOverlay)

        // Step 2 of Menu hierarchy: dismiss overlay
        #expect(viewModel.handleMenuPress())
        #expect(!viewModel.showOverlay)

        // Step 3 of Menu hierarchy: allow pop back to browser
        #expect(!viewModel.handleMenuPress())

        // Playlist navigation resets selection index cleanly
        viewModel.nextVideo()
        #expect(viewModel.currentIndex == 1)
        #expect(viewModel.activeEngineKind == .native)

        viewModel.previousVideo()
        #expect(viewModel.currentIndex == 0)
        #expect(viewModel.activeEngineKind == .extended)

        viewModel.tearDown()
    }

    @Test("Synchronizes Focus Engine targets across progress scrubber, playback buttons, and tracks sheet")
    @MainActor
    func testOverlayFocusTargetsAndTracksSheet() {
        let video1 = MediaSourceItem(
            id: "v1",
            name: "sample.mp4",
            path: "sample.mp4",
            type: .video,
            localURL: URL(fileURLWithPath: "/tmp/sample.mp4")
        )
        let video2 = MediaSourceItem(
            id: "v2",
            name: "sample2.mp4",
            path: "sample2.mp4",
            type: .video,
            localURL: URL(fileURLWithPath: "/tmp/sample2.mp4")
        )

        let viewModel = TVVideoPlayerViewModel(
            initialItem: video1,
            videos: [video1, video2],
            playbackStore: StubVideoPlaybackStore(),
            resolver: StubMediaSourceResolver()
        )

        viewModel.revealOverlay()
        #expect(viewModel.showOverlay)
        #expect(viewModel.currentFocusTarget == .playPause)

        viewModel.syncFocusTarget(.previous)
        #expect(viewModel.activeFocusRow == .buttons)
        #expect(viewModel.activeFocusedButton == .previous)

        viewModel.syncFocusTarget(.next)
        #expect(viewModel.activeFocusedButton == .next)

        viewModel.syncFocusTarget(.tracks)
        #expect(viewModel.activeFocusedButton == .tracks)

        viewModel.openTracksMenu()
        #expect(viewModel.isShowingTracksSheet)

        viewModel.syncFocusTarget(.progress)
        #expect(viewModel.activeFocusRow == .progress)
        viewModel.stepScrub(forward: true)
        #expect(viewModel.isScrubbing)
        #expect(viewModel.scrubbingTime == 10.0)

        viewModel.activateScrubberSelect()
        #expect(!viewModel.isScrubbing)
        #expect(viewModel.scrubbingTime == nil)

        viewModel.tearDown()
    }
}
