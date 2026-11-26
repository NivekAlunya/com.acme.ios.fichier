//
//  TVVideoPictureInPictureTests.swift
//  FichierTVTests
//

import Foundation
import Testing
@testable import FichierTV
import FichierKit

@Suite("TVVideoPictureInPicture Tests")
struct TVVideoPictureInPictureTests {
    @Test("TVVideoPictureInPictureCoordinator starts inactive and resets cleanly")
    @MainActor
    func testCoordinatorInitialStateAndReset() {
        let coordinator = TVVideoPictureInPictureCoordinator()

        #expect(coordinator.isPiPActive == false)
        #expect(coordinator.pipController == nil)

        coordinator.togglePiP()
        coordinator.reset()

        #expect(coordinator.isPiPActive == false)
        #expect(coordinator.pipController == nil)
    }

    @Test("TVVideoPlayerViewModel routes focus target .pip and toggles PiP safely")
    @MainActor
    func testViewModelPiPFocusAndToggle() {
        let video = MediaSourceItem(
            id: "v1",
            name: "sample.mkv",
            path: "sample.mkv",
            type: .video,
            localURL: URL(fileURLWithPath: "/tmp/sample.mkv")
        )
        let viewModel = TVVideoPlayerViewModel(
            initialItem: video,
            videos: [video],
            playbackStore: StubVideoPlaybackStore(),
            resolver: StubMediaSourceResolver()
        )
        defer { viewModel.tearDown() }

        viewModel.syncFocusTarget(.pip)
        #expect(viewModel.activeFocusRow == .buttons)
        #expect(viewModel.activeFocusedButton == .pip)
        #expect(viewModel.currentFocusTarget == .pip)

        viewModel.togglePiP()
        #expect(viewModel.isPiPActive == false)
    }
}
