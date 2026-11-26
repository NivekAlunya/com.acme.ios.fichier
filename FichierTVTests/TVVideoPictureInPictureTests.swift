//
//  TVVideoPictureInPictureTests.swift
//  FichierTVTests
//

import AVKit
import Foundation
import Testing
@testable import FichierTV
import FichierKit

@Suite("TVVideoPictureInPicture Tests")
struct TVVideoPictureInPictureTests {
    @Test("TVVideoPictureInPictureCoordinator starts inactive, deduplicates delegate callbacks, and resets cleanly")
    @MainActor
    func testCoordinatorLifecycleAndCallbackDeduplication() {
        let coordinator = TVVideoPictureInPictureCoordinator()
        var emissions: [Bool] = []
        coordinator.onPiPStatusChanged = { emissions.append($0) }

        #expect(coordinator.isPiPActive == false)
        #expect(coordinator.pipController == nil)

        coordinator.togglePiP()
        coordinator.reset()
        #expect(emissions.isEmpty)

        let dummyController = AVPictureInPictureController()
        coordinator.pictureInPictureControllerWillStartPictureInPicture(dummyController)
        coordinator.pictureInPictureControllerDidStartPictureInPicture(dummyController)
        #expect(coordinator.isPiPActive == true)
        #expect(emissions == [true])

        coordinator.pictureInPictureControllerDidStopPictureInPicture(dummyController)
        #expect(coordinator.isPiPActive == false)
        #expect(emissions == [true, false])

        coordinator.pictureInPictureControllerDidStartPictureInPicture(dummyController)
        coordinator.reset()
        #expect(coordinator.isPiPActive == false)
        #expect(coordinator.pipController == nil)
        #expect(emissions == [true, false, true, false])
    }

    @Test("TVVideoPlayerViewModel routes focus target .pip and steps focus by engine kind")
    @MainActor
    func testViewModelPiPFocusAndEngineSwitch() {
        let mp4 = MediaSourceItem(
            id: "v1",
            name: "sample.mp4",
            path: "sample.mp4",
            type: .video,
            localURL: URL(fileURLWithPath: "/tmp/sample.mp4")
        )
        let mkv = MediaSourceItem(
            id: "v2",
            name: "sample.mkv",
            path: "sample.mkv",
            type: .video,
            localURL: URL(fileURLWithPath: "/tmp/sample.mkv")
        )
        let viewModel = TVVideoPlayerViewModel(
            initialItem: mp4,
            videos: [mp4, mkv],
            playbackStore: StubVideoPlaybackStore(),
            resolver: StubMediaSourceResolver()
        )
        defer { viewModel.tearDown() }

        viewModel.loadCurrentVideo(preferredEngine: .native)
        viewModel.syncFocusTarget(.speed)
        viewModel.moveButtonFocus(forward: true)
        #expect(viewModel.activeFocusedButton == .pip)
        viewModel.moveButtonFocus(forward: true)
        #expect(viewModel.activeFocusedButton == .switchEngine)
        viewModel.moveButtonFocus(forward: false)
        #expect(viewModel.activeFocusedButton == .pip)

        viewModel.isPiPActive = true
        viewModel.loadCurrentVideo(preferredEngine: .extended)
        #expect(viewModel.isPiPActive == false)
        #expect(viewModel.activeFocusedButton == .playPause)

        viewModel.syncFocusTarget(.speed)
        viewModel.moveButtonFocus(forward: true)
        #expect(viewModel.activeFocusedButton == .switchEngine)
        viewModel.moveButtonFocus(forward: false)
        #expect(viewModel.activeFocusedButton == .speed)
    }

    @Test("TVVideoPlayerViewModel defers tearDown during PiP and tears down when PiP stops")
    @MainActor
    func testDeferredTearDownOnDisappearWhilePiPActive() {
        let video = MediaSourceItem(
            id: "v1",
            name: "sample.mp4",
            path: "sample.mp4",
            type: .video,
            localURL: URL(fileURLWithPath: "/tmp/sample.mp4")
        )
        let viewModel = TVVideoPlayerViewModel(
            initialItem: video,
            videos: [video],
            playbackStore: StubVideoPlaybackStore(),
            resolver: StubMediaSourceResolver()
        )

        viewModel.isPiPActive = true
        viewModel.handleViewDisappear()
        #expect(viewModel.hasDisappeared == true)

        viewModel.isPiPActive = false
        #expect(viewModel.hasDisappeared == false)
    }
}
