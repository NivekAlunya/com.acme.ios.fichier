//
//  VideoPlayerControllerFlowTests.swift
//  fichierTests
//
//  Created for testing VideoPlayerController state flows, error sanitization, and engine seeking.
//

#if DEBUG
import Foundation
import AVFoundation
import Testing
import FichierKit
@testable import fichier

@Suite("VideoPlayerController & Engine Flow Tests")
@MainActor
struct VideoPlayerControllerFlowTests {

    private func makeVideoItem(name: String, path: String = "/Videos/clip.mp4") -> MediaItem {
        MediaItem(
            locationID: "alice@nas.local",
            name: name,
            rootName: "Media",
            path: path,
            isDirectory: false,
            size: 4096
        )
    }

    @Test("Playlist filtering ignores non-video files and falls back to initialItem if none qualify")
    func playlistFilteringAndFallback() {
        let manager = StorageLocationManager()
        let photo = MediaItem(locationID: "loc", name: "photo.jpg", rootName: "Media", path: "/photo.jpg", isDirectory: false)
        let video1 = makeVideoItem(name: "one.mp4", path: "/one.mp4")
        let video2 = makeVideoItem(name: "two.mkv", path: "/two.mkv")

        let mixed = VideoPlayerController(manager: manager, videos: [photo, video1, video2], initialItem: video1)
        #expect(mixed.videos.map(\.id) == [video1.id, video2.id])
        #expect(mixed.playbackState == .idle)

        let fallback = VideoPlayerController(manager: manager, videos: [photo], initialItem: photo)
        #expect(fallback.videos.map(\.id) == [photo.id])
    }

    @Test("Missing SMB client during remote stream setup transitions cleanly to failed state")
    func missingClientRemoteStreamTransitionsToFailedState() async {
        let manager = StorageLocationManager()
        let remoteVideo = makeVideoItem(name: "movie.mkv", path: "/Movies/movie.mkv")
        let controller = VideoPlayerController(manager: manager, videos: [remoteVideo], initialItem: remoteVideo)

        controller.setupPlayer(for: remoteVideo)

        for _ in 0..<50 {
            if case .failed = controller.playbackState {
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }

        if case .failed(let message) = controller.playbackState {
            #expect(!message.isEmpty)
            #expect(controller.errorMessage == message)
        } else {
            Issue.record("Expected playbackState to transition to .failed when no SMB client is active")
        }

        controller.tearDownPlayer(deactivateAudioSession: false)
        #expect(controller.playbackState == .idle)
        #expect(controller.errorMessage == nil)
        #expect(controller.currentlyLoadedItem == nil)
    }

    @Test("Direct SMB URL construction failure for extended format transitions to failed state")
    func directSMBURLFailureTransitionsToFailedState() async {
        let manager = StorageLocationManager()
        // Path with invalid/empty share structure
        let invalidItem = makeVideoItem(name: "trailer.mkv", path: "///")
        let controller = VideoPlayerController(manager: manager, videos: [invalidItem], initialItem: invalidItem)

        controller.setupPlayer(for: invalidItem)

        for _ in 0..<50 {
            if case .failed = controller.playbackState {
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }

        if case .failed(let message) = controller.playbackState {
            #expect(!message.isEmpty)
            #expect(controller.errorMessage == message)
        } else {
            Issue.record("Expected playbackState to transition to .failed when direct SMB URL cannot be created")
        }

        controller.tearDownPlayer(deactivateAudioSession: false)
    }

    @Test("Playback error handling redacts IPv4 addresses and SMB credentials")
    func errorSanitizationRedactsSensitiveHostAndCredentials() {
        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichier_player_test_\(UUID().uuidString).mp4")
        let localItem = MediaItem(
            locationID: "local",
            name: tempVideoURL.lastPathComponent,
            rootName: "Temp",
            path: tempVideoURL.lastPathComponent,
            isDirectory: false,
            localURL: tempVideoURL
        )

        let manager = StorageLocationManager()
        let controller = VideoPlayerController(manager: manager, videos: [localItem], initialItem: localItem)
        controller.setupPlayer(for: localItem)
        defer { controller.tearDownPlayer(deactivateAudioSession: false) }

        guard let currentItem = controller.player?.currentItem else {
            Issue.record("Expected AVPlayerItem to be mounted on native player")
            return
        }

        let sensitiveError = NSError(
            domain: "SMBStream",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Failed smb://kevin:secret@192.168.1.42/Share at 192.168.1.42"]
        )
        let notification = Notification(
            name: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: currentItem,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: sensitiveError]
        )

        controller.handleItemFailedToPlayToEndTime(notification)

        #expect(controller.errorMessage != nil)
        #expect(controller.errorMessage?.contains("192.168.1.42") == false)
        #expect(controller.errorMessage?.contains("kevin:secret") == false)
        #expect(controller.errorMessage?.contains("<host>") == true)
        #expect(controller.errorMessage?.contains("smb://<server>") == true)
        if case .failed = controller.playbackState {
        } else {
            Issue.record("Expected failed playback state after AVPlayerItem error notification")
        }
    }

    @Test("VideoSeekCoordinator dispatches infinity tolerance and resumes MockPlayerEngine")
    func seekCoordinatorWorksWithMockPlayerEngine() async {
        let coordinator = VideoSeekCoordinator()
        let engine = MockPlayerEngine()
        engine.play()
        #expect(engine.isPlaying)

        coordinator.startTimelineScrubbing(currentPlaybackSeconds: 10.0, isPlaying: true, engine: engine)
        #expect(coordinator.wasPlayingBeforeScrub)
        #expect(engine.pauseCount == 1)
        #expect(!engine.isPlaying)

        coordinator.requestLiveFrameSeek(to: 45.0, engine: engine)
        #expect(engine.seekCalls.count == 1)
        #expect(engine.seekCalls[0].seconds == 45.0)
        #expect(engine.seekCalls[0].toleranceBefore.isInfinite)
        #expect(engine.seekCalls[0].toleranceAfter.isInfinite)

        var completionCalled = false
        coordinator.finishSeeking(
            at: 45.0,
            resumePlaying: true,
            engine: engine,
            onBuffering: nil,
            onComplete: {
                completionCalled = true
            }
        )
        coordinator.endTimelineScrubbing()

        for _ in 0..<20 where !completionCalled {
            await Task.yield()
        }

        #expect(completionCalled)
        #expect(!coordinator.isFinishingSeek)
        #expect(!coordinator.isScrubbing)
        #expect(engine.isPlaying)
        #expect(engine.seekCalls.count == 2)
        #expect(engine.seekCalls[1].seconds == 45.0)
        #expect(engine.seekCalls[1].toleranceBefore == 1.0)
    }

    @Test("switchEngine switches engine kind and starts from beginning")
    func switchEngineTogglesEngineKind() {
        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichier_switch_test_\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: tempVideoURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        let item = MediaItem(
            locationID: "local",
            name: tempVideoURL.lastPathComponent,
            rootName: "Temp",
            path: tempVideoURL.lastPathComponent,
            isDirectory: false,
            localURL: tempVideoURL
        )

        let manager = StorageLocationManager()
        let controller = VideoPlayerController(manager: manager, videos: [item], initialItem: item)
        controller.setupPlayer(for: item)
        defer { controller.tearDownPlayer(deactivateAudioSession: false) }

        #expect(controller.engineKind == .native)

        controller.switchEngine()
        #expect(controller.engineKind == .extended)
        #expect(controller.currentPlaybackSeconds == 0)

        controller.switchEngine()
        #expect(controller.engineKind == .native)
        #expect(controller.currentPlaybackSeconds == 0)
    }
}
#endif
