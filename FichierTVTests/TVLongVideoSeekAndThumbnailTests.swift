//
//  TVLongVideoSeekAndThumbnailTests.swift
//  FichierTVTests
//
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import FichierTV
import FichierKit

@Suite("Long-Video Seek & Thumbnail Preview Tests")
struct TVLongVideoSeekAndThumbnailTests {
    @Test("Duration-scaled hold curve and scrub steps preserve short-clip precision and accelerate on 2h movies")
    func testDurationScaledHoldAndScrubCurves() {
        // Short clip (400s <= 600s) preserves baseline curve
        #expect(abs(TVRemoteSeekCalculator.progressiveHoldMagnitude(for: 2.30, totalDuration: 400.0) - 55.0) < 0.001)
        #expect(abs(TVRemoteSeekCalculator.progressiveHoldMagnitude(for: 5.30, totalDuration: 400.0) - 190.0) < 0.001)
        #expect(TVRemoteSeekCalculator.scrubStepMagnitude(consecutiveSteps: 1, totalDuration: 400.0) == 10.0)
        #expect(TVRemoteSeekCalculator.scrubStepMagnitude(consecutiveSteps: 9, totalDuration: 400.0) == 60.0)

        // 2-hour movie (7200s): starts at 15s, remains continuous at tier boundaries, and traverses ~1h 18m by 7.3s hold
        let atThreshold = TVRemoteSeekCalculator.progressiveHoldMagnitude(for: 0.30, totalDuration: 7200.0)
        let atFourPointThree = TVRemoteSeekCalculator.progressiveHoldMagnitude(for: 4.30, totalDuration: 7200.0)
        let atSevenPointThree = TVRemoteSeekCalculator.progressiveHoldMagnitude(for: 7.30, totalDuration: 7200.0)
        #expect(abs(atThreshold - 15.0) < 0.001)
        #expect(atFourPointThree > 1400.0 && atFourPointThree < 1600.0)
        #expect(atSevenPointThree > 4500.0 && atSevenPointThree < 5000.0)

        // Scaled HUD scrub steps for 2h movie
        #expect(TVRemoteSeekCalculator.scrubStepMagnitude(consecutiveSteps: 1, totalDuration: 7200.0) == 40.0)
        #expect(TVRemoteSeekCalculator.scrubStepMagnitude(consecutiveSteps: 4, totalDuration: 7200.0) == 120.0)
        #expect(TVRemoteSeekCalculator.scrubStepMagnitude(consecutiveSteps: 6, totalDuration: 7200.0) == 300.0)
    }

    @Test("Swipe scrub delta scaling and pan recognizer horizontal-vs-vertical discrimination")
    @MainActor
    func testTouchpadSwipeScalingAndPanCapture() {
        let slowDelta = TVRemoteSeekCalculator.swipeScrubDelta(
            translationDeltaX: 200.0,
            velocityX: 120.0,
            trackWidth: 1800.0,
            totalDuration: 7200.0
        )
        let normalDelta = TVRemoteSeekCalculator.swipeScrubDelta(
            translationDeltaX: 200.0,
            velocityX: 600.0,
            trackWidth: 1800.0,
            totalDuration: 7200.0
        )
        let flickDelta = TVRemoteSeekCalculator.swipeScrubDelta(
            translationDeltaX: 200.0,
            velocityX: 2600.0,
            trackWidth: 1800.0,
            totalDuration: 7200.0
        )
        #expect(slowDelta > 0)
        #expect(normalDelta > slowDelta * 2.0)
        #expect(flickDelta > normalDelta * 1.5)
        #expect(TVRemoteSeekCalculator.swipeScrubDelta(translationDeltaX: 100.0, velocityX: 400.0, trackWidth: 1800.0, totalDuration: 0.0) == 0.0)

        let panView = TVOverlayPanCaptureUIView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(!panView.canBecomeFocused)
        #expect(!panView.shouldBeginSwipe(translation: CGPoint(x: 120, y: 0), velocity: CGPoint(x: 800, y: 0)))

        panView.isScrubberSwipeEnabled = true
        #expect(panView.shouldBeginSwipe(translation: CGPoint(x: 90, y: 12), velocity: CGPoint(x: 600, y: 40)))
        #expect(!panView.shouldBeginSwipe(translation: CGPoint(x: 12, y: 80), velocity: CGPoint(x: 40, y: 500)))

        var events: [String] = []
        panView.onPanChanged = { dx, vx, width in
            events.append("changed:\(Int(dx)):\(Int(vx)):\(Int(width))")
        }
        panView.onPanEnded = {
            events.append("ended")
        }
        panView.processPanEvent(incrementalDeltaX: 140, velocityX: 900, trackWidth: 1800, state: .changed)
        panView.processPanEvent(incrementalDeltaX: 0, velocityX: 0, trackWidth: 1800, state: .ended)
        #expect(events == ["changed:140:900:1800", "ended"])
    }

    @Test("Quick-jump presets and chapter menu jump commit fast seek without corrupting hold state")
    @MainActor
    func testQuickJumpOptionsAndJumpToTime() {
        let options = TVVideoQuickJumpOption.buildOptions(duration: 7200.0, currentTime: 1800.0)
        #expect(options.map(\.label) == ["Start (0%)", "25%", "50%", "75%", "-10 min", "+10 min", "+30 min"])
        #expect(options[1].targetTime == 1800.0)
        #expect(options[2].targetTime == 3600.0)
        #expect(options[3].targetTime == 5400.0)

        let clock = StubUptimeClock(now: 100.0)
        let video = MediaSourceItem(
            id: "v_long",
            name: "movie.mp4",
            path: "movie.mp4",
            type: .video,
            localURL: URL(fileURLWithPath: "/tmp/movie.mp4")
        )
        let viewModel = TVVideoPlayerViewModel(
            initialItem: video,
            videos: [video],
            playbackStore: StubVideoPlaybackStore(),
            resolver: StubMediaSourceResolver(),
            remoteCommandBridge: StubRemoteCommandBridge(),
            thumbnailProvider: StubSeekThumbnailProvider(),
            uptimeProvider: { clock.now }
        )
        defer { viewModel.tearDown() }

        viewModel.nativeEngine.onDurationUpdate?(7200.0)
        viewModel.syncFocusTarget(.chapters)
        #expect(viewModel.currentFocusTarget == .chapters)

        viewModel.openChaptersMenu()
        #expect(viewModel.isShowingChaptersSheet)

        viewModel.jumpToTime(3600.0)
        #expect(abs(viewModel.currentTime - 3600.0) < 0.001)
        #expect(viewModel.remoteSeekPreview?.targetTime == 3600.0)
        #expect(viewModel.remoteSeekPreview?.deltaSeconds == 3600.0)
    }

    @Test("Seek thumbnail worker updates preview frame during hold, hits bucket cache, and cancels on Menu")
    @MainActor
    func testSeekThumbnailWorkerCoalescingAndCancellation() async throws {
        let syntheticURL = URL(fileURLWithPath: "/tmp/long_movie_thumb_test.mp4")

        let clock = StubUptimeClock(now: 250.0)
        let stubThumbProvider = StubSeekThumbnailProvider(delayNanoseconds: 20_000_000)
        let video = MediaSourceItem(
            id: "v_thumb_worker",
            name: "sample.mp4",
            path: "sample.mp4",
            type: .video,
            localURL: syntheticURL
        )
        let viewModel = TVVideoPlayerViewModel(
            initialItem: video,
            videos: [video],
            playbackStore: StubVideoPlaybackStore(),
            resolver: StubMediaSourceResolver(),
            remoteCommandBridge: StubRemoteCommandBridge(),
            thumbnailProvider: stubThumbProvider,
            uptimeProvider: { clock.now }
        )
        defer { viewModel.tearDown() }

        viewModel.setResolvedMediaURLForTesting(syntheticURL)
        viewModel.nativeEngine.onDurationUpdate?(7200.0)
        viewModel.nativeEngine.seek(to: 100.0, precision: .exact)

        // Start hold and scrub rapidly across multiple timestamps before settle -> single-flight coalesces to 1 decode
        viewModel.beginRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 250.0)
        clock.now = 251.0
        viewModel.refreshActiveRemoteSeekPreview(at: 251.0)
        clock.now = 252.0
        viewModel.refreshActiveRemoteSeekPreview(at: 252.0)
        #expect(viewModel.seekThumbnailState?.isLoading == true)
        #expect(abs(viewModel.currentTime - 100.0) < 0.001)

        // Wait for single-flight settle + stub generation
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 30_000_000)
            if viewModel.seekThumbnailState?.image != nil && viewModel.seekThumbnailState?.isLoading == false {
                break
            }
        }
        #expect(viewModel.seekThumbnailState?.image != nil)
        #expect(viewModel.seekThumbnailState?.isLoading == false)
        let countAfterFirstDecode = await stubThumbProvider.requestCount()
        #expect(countAfterFirstDecode == 1)

        // Revisiting exact same bucket serves synchronously from ViewModel cache without extra decode call
        let decodedBucketTarget = try #require(viewModel.seekThumbnailState?.bucketTime)
        viewModel.endRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 252.0)
        viewModel.jumpToTime(decodedBucketTarget)
        viewModel.revealOverlay()
        viewModel.updateSwipeScrub(translationDeltaX: 1.0, velocityX: 100.0, trackWidth: 1800.0)
        #expect(viewModel.seekThumbnailState?.image != nil)
        #expect(viewModel.seekThumbnailState?.isLoading == false)
        try? await Task.sleep(nanoseconds: 120_000_000)
        let countAfterRevisit = await stubThumbProvider.requestCount()
        #expect(countAfterRevisit == countAfterFirstDecode)

        // Menu during hold cancels thumbnail state cleanly
        clock.now = 270.0
        viewModel.beginRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 270.0)
        clock.now = 271.5
        viewModel.refreshActiveRemoteSeekPreview(at: 271.5)
        #expect(viewModel.seekThumbnailState != nil)
        #expect(viewModel.handleMenuPress())
        #expect(viewModel.seekThumbnailState == nil)
        #expect(!viewModel.isRemoteSeekHolding)
    }

    @Test("TVSeekThumbnailService extracts real frames via AVAssetImageGenerator and VLCVideoThumbnailActor and quantizes buckets")
    func testRealNativeAndExtendedThumbnailService() async throws {
        #expect(TVSeekThumbnailService.bucketTimestamp(targetTime: 13.4, duration: 120.0) == 14.0)
        #expect(TVSeekThumbnailService.bucketTimestamp(targetTime: 1844.0, duration: 7200.0) == 1830.0)
        #expect(TVSeekThumbnailService.bucketTimestamp(targetTime: 7200.0, duration: 7200.0) == 7170.0)

        let tempVideoURL = try await TVVideoTestFixtureGenerator.createSampleMP4File()
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        let service = TVSeekThumbnailService()
        let nativeRequest = TVSeekThumbnailRequest(
            url: tempVideoURL,
            assetKey: "real_mp4",
            targetTime: 1.0,
            duration: 3.0,
            engineKind: .native,
            maxDimension: 320
        )
        let nativeImage = await service.generateThumbnail(for: nativeRequest)
        let verifiedNative = try #require(nativeImage)
        #expect(verifiedNative.size.width > 0)
        #expect(await service.cachedThumbnail(for: nativeRequest) != nil)

        let extendedRequest = TVSeekThumbnailRequest(
            url: tempVideoURL,
            assetKey: "real_vlc",
            targetTime: 1.0,
            duration: 3.0,
            engineKind: .extended,
            maxDimension: 320
        )
        let extendedImage = await service.generateThumbnail(for: extendedRequest)
        let verifiedExtended = try #require(extendedImage)
        #expect(verifiedExtended.size.width > 0)

        await service.invalidateAsset(forAssetKey: "real_mp4")
        #expect(await service.cachedThumbnail(for: nativeRequest) == nil)
    }

    @Test("Floating thumbnail preview card and Chapters button preserve Focus Engine contracts")
    @MainActor
    func testThumbnailCardAndChaptersButtonFocusHostContracts() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 90))
        let stubImage = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        }
        let thumbState = TVSeekThumbnailState(
            targetTime: 1800.0,
            bucketTime: 1800.0,
            image: stubImage,
            isLoading: false
        )
        let sampleChapters = [
            PlayerChapter(id: "c1", title: "Opening", startTime: 0, duration: 900),
            PlayerChapter(id: "c2", title: "Act II", startTime: 1800, duration: 1800)
        ]

        let overlayController = UIHostingController(
            rootView: TVVideoOverlayControlsView(
                title: "Epic.mkv",
                currentTime: 900,
                duration: 7200,
                isPlaying: true,
                isScrubbing: true,
                scrubbingTime: 1800,
                chapters: sampleChapters,
                seekThumbnailState: thumbState,
                isTracksSheetPresented: false,
                initialFocusTarget: .playPause,
                onFocusChanged: { _ in },
                onScrubStep: { _ in },
                onScrubberSelect: {},
                onPrevious: {},
                onTogglePlayPause: {},
                onNext: {},
                onOpenChapters: {},
                onOpenTracks: {}
            )
        )

        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.rootViewController = overlayController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            overlayController.view.layoutIfNeeded()
            window.updateFocusIfNeeded()
            let count = countFocusableItems(in: overlayController.view, bounds: window.bounds)
            if count >= 6 {
                break
            }
        }

        // 7 buttons (Previous, Play/Pause, Next, Chapters, Tracks, Speed, SwitchEngine) + 1 scrubber = 8 focusable items;
        // floating thumbnail card and pan capture must NOT add any focusable elements.
        let focusCount = countFocusableItems(in: overlayController.view, bounds: window.bounds)
        #expect(focusCount == 8)

        // Verify hidden-overlay seek preview with thumbnail card still leaves catcher as the ONLY focusable item
        let previewController = UIHostingController(
            rootView: ZStack {
                TVPlayerRemoteCatcherView(
                    isEnabled: true,
                    shouldRequestFocus: true,
                    onSeekPressBegan: { _, _ in },
                    onSeekPressEnded: { _, _ in },
                    onSeekPressCancelled: { _ in },
                    onRevealOverlay: {}
                )
                TVVideoSeekPreviewHUDView(
                    engineKind: .extended,
                    duration: 7200,
                    preview: TVRemoteSeekPreview(targetTime: 1800, deltaSeconds: 900, isHolding: true),
                    chapters: sampleChapters
                )
            }
        )
        window.rootViewController = previewController
        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 40_000_000)
            previewController.view.layoutIfNeeded()
            window.updateFocusIfNeeded()
        }
        #expect(countFocusableItems(in: previewController.view, bounds: window.bounds) == 1)
    }

    @MainActor
    private func countFocusableItems(in environment: any UIFocusEnvironment, bounds: CGRect) -> Int {
        var visitedIDs: Set<ObjectIdentifier> = []
        var count = 0

        func visit(_ env: any UIFocusEnvironment) {
            if let obj = env as AnyObject? {
                let id = ObjectIdentifier(obj)
                if !visitedIDs.insert(id).inserted {
                    return
                }
            }
            if let item = env as? any UIFocusItem, item.canBecomeFocused {
                count += 1
            }
            if let container = env as? any UIFocusItemContainer {
                for child in container.focusItems(in: bounds) {
                    visit(child)
                }
            } else if let view = env as? UIView {
                for item in view.focusItems(in: bounds) {
                    visit(item)
                }
                for subview in view.subviews {
                    visit(subview)
                }
            }
        }

        visit(environment)
        return count
    }
}
