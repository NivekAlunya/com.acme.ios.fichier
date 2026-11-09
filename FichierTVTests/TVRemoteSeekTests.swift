//
//  TVRemoteSeekTests.swift
//  FichierTVTests
//
//

import Foundation
import Testing
import UIKit
@testable import FichierTV
import FichierKit

@Suite("TVRemoteSeek Tests")
struct TVRemoteSeekTests {
    @Test("Progressive hold curve is continuous across all acceleration tiers")
    func testProgressiveHoldCurveAndFormatting() {
        #expect(TVRemoteSeekCalculator.progressiveHoldMagnitude(for: 0.0) == 15.0)
        #expect(TVRemoteSeekCalculator.progressiveHoldMagnitude(for: 0.29) == 15.0)
        #expect(abs(TVRemoteSeekCalculator.progressiveHoldMagnitude(for: 0.30) - 15.0) < 0.0001)
        #expect(abs(TVRemoteSeekCalculator.progressiveHoldMagnitude(for: 1.30) - 35.0) < 0.0001)
        #expect(abs(TVRemoteSeekCalculator.progressiveHoldMagnitude(for: 2.30) - 55.0) < 0.0001)
        #expect(abs(TVRemoteSeekCalculator.progressiveHoldMagnitude(for: 3.30) - 100.0) < 0.0001)
        #expect(abs(TVRemoteSeekCalculator.progressiveHoldMagnitude(for: 5.30) - 190.0) < 0.0001)
        #expect(abs(TVRemoteSeekCalculator.progressiveHoldMagnitude(for: 7.30) - 370.0) < 0.0001)

        #expect(TVRemoteSeekCalculator.clampedTarget(from: 100.0, signedDelta: 30.0, duration: 120.0) == 120.0)
        #expect(TVRemoteSeekCalculator.clampedTarget(from: 10.0, signedDelta: -30.0, duration: 120.0) == 0.0)
        #expect(TVRemoteSeekCalculator.clampedTarget(from: 100.0, signedDelta: 45.0, duration: 0.0) == 145.0)

        #expect(TVRemoteSeekCalculator.formattedDelta(15.0) == "+15s")
        #expect(TVRemoteSeekCalculator.formattedDelta(-15.0) == "-15s")
        #expect(TVRemoteSeekCalculator.formattedDelta(60.0) == "+60s")
        #expect(TVRemoteSeekCalculator.formattedDelta(95.0) == "+1m 35s")
        #expect(TVRemoteSeekCalculator.formattedDelta(-120.0) == "-2m")
        #expect(TVRemoteSeekCalculator.formattedDelta(0.0) == "0s")
        #expect(TVRemoteSeekCalculator.formattedTimestamp(3930.0) == "01:05:30")
    }

    @Test("Single short tap (< 0.30s) skips 15s and double tap within 0.50s skips 60s total")
    @MainActor
    func testTapAndDoubleTapWithinWindow() {
        let clock = StubUptimeClock(now: 500.0)
        let bridge = StubRemoteCommandBridge()
        let video = makeTestVideoItem()

        let viewModel = TVVideoPlayerViewModel(
            initialItem: video,
            videos: [video],
            playbackStore: StubVideoPlaybackStore(),
            resolver: StubMediaSourceResolver(),
            remoteCommandBridge: bridge,
            uptimeProvider: { clock.now }
        )
        defer { viewModel.tearDown() }

        viewModel.nativeEngine.onDurationUpdate?(600.0)
        viewModel.nativeEngine.seek(to: 100.0)

        // Tap 1 (< 0.30s held): +15s immediately
        viewModel.beginRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 500.00)
        viewModel.endRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 500.12)
        #expect(viewModel.currentTime == 115.0)
        #expect(viewModel.remoteSeekPreview == TVRemoteSeekPreview(targetTime: 115.0, deltaSeconds: 15.0, isHolding: false))

        // Simulate SMB periodic observer temporarily reverting currentTime before engine settles
        viewModel.nativeEngine.onTimeUpdate?(100.2)
        #expect(viewModel.currentTime == 100.2)

        // Tap 2 within 0.50s (release 500.40 - 500.12 = 0.28s): lands at origin 100 + 60 = 160s!
        viewModel.beginRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 500.28)
        viewModel.endRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 500.40)
        #expect(viewModel.currentTime == 160.0)
        #expect(viewModel.remoteSeekPreview == TVRemoteSeekPreview(targetTime: 160.0, deltaSeconds: 60.0, isHolding: false))

        // Tap 3 immediately after double tap starts a fresh +15s step -> 175s
        viewModel.beginRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 500.55)
        viewModel.endRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 500.65)
        #expect(viewModel.currentTime == 175.0)
        #expect(viewModel.remoteSeekPreview == TVRemoteSeekPreview(targetTime: 175.0, deltaSeconds: 15.0, isHolding: false))
    }

    @Test("Taps separated by more than 0.50s or opposite direction skip 15s without 60s upgrade")
    @MainActor
    func testTapOutsideWindowAndDirectionReversal() {
        let clock = StubUptimeClock(now: 100.0)
        let viewModel = makeViewModel(clock: clock)
        defer { viewModel.tearDown() }

        viewModel.nativeEngine.onDurationUpdate?(600.0)
        viewModel.nativeEngine.seek(to: 100.0)

        // Tap 1 at 100.10
        viewModel.beginRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 100.00)
        viewModel.endRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 100.10)
        #expect(viewModel.currentTime == 115.0)

        // Tap 2 at 100.65 (gap 0.55s > 0.50s) -> +15s (130.0)
        viewModel.beginRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 100.56)
        viewModel.endRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 100.65)
        #expect(viewModel.currentTime == 130.0)

        // Opposite direction within 0.50s -> -15s (back to 115.0)
        viewModel.beginRemoteSeek(isForward: false, source: .siriRemoteDirection, timestamp: 100.75)
        viewModel.endRemoteSeek(isForward: false, source: .siriRemoteDirection, timestamp: 100.85)
        #expect(viewModel.currentTime == 115.0)
        #expect(viewModel.remoteSeekPreview?.deltaSeconds == -15.0)

        // Second backward tap within 0.50s -> double-tap backward to 130 - 60 = 70.0!
        viewModel.beginRemoteSeek(isForward: false, source: .siriRemoteDirection, timestamp: 101.00)
        viewModel.endRemoteSeek(isForward: false, source: .siriRemoteDirection, timestamp: 101.10)
        #expect(viewModel.currentTime == 70.0)
        #expect(viewModel.remoteSeekPreview?.deltaSeconds == -60.0)
    }

    @Test("Press-and-hold updates live preview progressively and commits single clamped seek on release")
    @MainActor
    func testProgressiveHoldSeekAndAutoRepeatGuard() {
        let clock = StubUptimeClock(now: 200.0)
        let viewModel = makeViewModel(clock: clock)
        defer { viewModel.tearDown() }

        viewModel.nativeEngine.onDurationUpdate?(400.0)
        viewModel.nativeEngine.seek(to: 50.0)

        // Begin forward hold at t = 200.0
        viewModel.beginRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 200.0)
        #expect(viewModel.isRemoteSeekHolding)
        #expect(viewModel.currentTime == 50.0)

        // Duplicate begin from auto-repeat must NOT reset anchor or start timestamp
        viewModel.beginRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 201.5)

        // At elapsed = 2.30s -> delta = +55s (target = 105s), playback stays uninterrupted at 50s
        viewModel.refreshActiveRemoteSeekPreview(at: 202.30)
        #expect(viewModel.remoteSeekPreview?.isHolding == true)
        #expect(abs((viewModel.remoteSeekPreview?.targetTime ?? -1) - 105.0) < 0.001)
        #expect(abs((viewModel.remoteSeekPreview?.deltaSeconds ?? -1) - 55.0) < 0.001)
        #expect(abs(viewModel.currentTime - 50.0) < 0.001)

        // Release at elapsed = 5.30s -> commits +190s (50 + 190 = 240s) in a single seek
        viewModel.endRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 205.30)
        #expect(!viewModel.isRemoteSeekHolding)
        #expect(abs(viewModel.currentTime - 240.0) < 0.001)
        #expect(viewModel.remoteSeekPreview?.isHolding == false)
        #expect(abs((viewModel.remoteSeekPreview?.targetTime ?? -1) - 240.0) < 0.001)
        #expect(abs((viewModel.remoteSeekPreview?.deltaSeconds ?? -1) - 190.0) < 0.001)

        // Holding forward past EOF clamps at duration (400s) and reports actual delta (+160s)
        viewModel.beginRemoteSeek(isForward: true, source: .hardwareMediaCommand, timestamp: 210.0)
        viewModel.endRemoteSeek(isForward: true, source: .hardwareMediaCommand, timestamp: 216.0)
        #expect(abs(viewModel.currentTime - 400.0) < 0.001)
        #expect(viewModel.remoteSeekPreview?.isHolding == false)
        #expect(abs((viewModel.remoteSeekPreview?.targetTime ?? -1) - 400.0) < 0.001)
        #expect(abs((viewModel.remoteSeekPreview?.deltaSeconds ?? -1) - 160.0) < 0.001)
    }

    @Test("Menu press during hold cancels seek, clears preview, and ignores delayed release")
    @MainActor
    func testMenuPressCancelsHoldWithoutSeeking() {
        let clock = StubUptimeClock(now: 300.0)
        let viewModel = makeViewModel(clock: clock)
        defer { viewModel.tearDown() }

        viewModel.nativeEngine.onDurationUpdate?(600.0)
        viewModel.nativeEngine.seek(to: 120.0)

        viewModel.beginRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 300.0)
        viewModel.refreshActiveRemoteSeekPreview(at: 302.0)
        #expect(viewModel.remoteSeekPreview?.isHolding == true)
        #expect(!viewModel.showOverlay)

        // Menu cancels hold without opening/closing overlay or popping
        let handled = viewModel.handleMenuPress()
        #expect(handled)
        #expect(!viewModel.isRemoteSeekHolding)
        #expect(viewModel.remoteSeekPreview == nil)
        #expect(viewModel.currentTime == 120.0)
        #expect(!viewModel.showOverlay)

        // Lifting thumb afterwards must NOT commit any seek or tap skip
        viewModel.endRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 302.5)
        #expect(viewModel.currentTime == 120.0)
        #expect(viewModel.remoteSeekPreview == nil)
    }

    @Test("Hardware MediaPlayer remote commands work with HUD visible and tearDown cleans up bridge")
    @MainActor
    func testHardwareMediaRemoteBridgeLifecycleAndDeduplication() async throws {
        let videoURL = try await TVVideoTestFixtureGenerator.createSampleMP4File()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let clock = StubUptimeClock(now: 400.0)
        let bridge = StubRemoteCommandBridge()
        let video = MediaSourceItem(
            id: "v_real",
            name: "sample.mp4",
            path: "sample.mp4",
            type: .video,
            localURL: videoURL
        )

        let viewModel = TVVideoPlayerViewModel(
            initialItem: video,
            videos: [video],
            playbackStore: StubVideoPlaybackStore(),
            resolver: StubMediaSourceResolver(),
            remoteCommandBridge: bridge,
            uptimeProvider: { clock.now }
        )

        viewModel.loadCurrentVideo()
        #expect(bridge.activateCount == 1)
        #expect(!bridge.nowPlayingUpdates.isEmpty)

        viewModel.nativeEngine.onDurationUpdate?(500.0)
        viewModel.nativeEngine.seek(to: 200.0)

        // Show full HUD: hardware << / >> still work without hiding overlay
        viewModel.revealOverlay()
        #expect(viewModel.showOverlay)

        bridge.simulateSeekBegan(isForward: false, timestamp: 400.0)
        bridge.simulateSeekEnded(isForward: false, timestamp: 401.3)
        #expect(abs(viewModel.currentTime - 165.0) < 0.001)
        #expect(viewModel.showOverlay)

        // Unpaired endSeeking (buggy CEC remote) gracefully falls back to 15s/60s tap skip
        bridge.simulateSeekEnded(isForward: true, timestamp: 405.0)
        #expect(abs(viewModel.currentTime - 180.0) < 0.001)
        bridge.simulateSeekEnded(isForward: true, timestamp: 405.35)
        #expect(abs(viewModel.currentTime - 225.0) < 0.001)

        // Play/Pause deduplication: local Siri press + <80ms MediaRemote echo does NOT double-toggle
        let initialPlaying = viewModel.isPlaying
        viewModel.handlePlayPauseCommand()
        #expect(viewModel.isPlaying != initialPlaying)
        bridge.simulateTogglePlayPause(timestamp: 400.03)
        #expect(viewModel.isPlaying != initialPlaying)

        viewModel.tearDown()
        #expect(bridge.deactivateCount == 1)
    }

    @Test("TVPlayerRemoteCatcherUIView captures left/right durations, reveals on up/down/selectEnded, and passes menu through")
    @MainActor
    func testRemoteCatcherUIViewPressMapping() {
        let view = TVPlayerRemoteCatcherUIView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        var events: [String] = []

        view.onSeekPressBegan = { forward, ts in
            events.append("began:\(forward):\(Int(ts))")
        }
        view.onSeekPressEnded = { forward, ts in
            events.append("ended:\(forward):\(Int(ts))")
        }
        view.onSeekPressCancelled = { forward in
            events.append("cancelled:\(forward)")
        }
        view.onRevealOverlay = {
            events.append("reveal")
        }

        let rightPress = MockRemoteUIPress(type: .rightArrow, timestamp: 10.0)
        let rightEnd = MockRemoteUIPress(type: .rightArrow, timestamp: 12.0)
        view.pressesBegan([rightPress], with: nil)
        // Duplicate same-press began (key repeat) is ignored
        view.pressesBegan([rightPress], with: nil)
        #expect(events == ["began:true:10"])

        view.pressesEnded([rightPress], with: nil)
        // Unrelated extra end press does not fire
        view.pressesEnded([rightEnd], with: nil)
        #expect(events == ["began:true:10", "ended:true:10"])

        // Select must NOT reveal on began, only on ended (prevents accidental HUD button tap)
        events.removeAll()
        let selectPress = MockRemoteUIPress(type: .select, timestamp: 20.0)
        view.pressesBegan([selectPress], with: nil)
        #expect(events.isEmpty)
        view.pressesEnded([selectPress], with: nil)
        #expect(events == ["reveal"])

        // Cancelled seek press triggers cancellation without ended
        events.removeAll()
        let leftPress = MockRemoteUIPress(type: .leftArrow, timestamp: 30.0)
        view.pressesBegan([leftPress], with: nil)
        view.pressesCancelled([leftPress], with: nil)
        #expect(events == ["began:false:30", "cancelled:false"])
    }

    @MainActor
    private func makeViewModel(clock: StubUptimeClock) -> TVVideoPlayerViewModel {
        let video = makeTestVideoItem()
        return TVVideoPlayerViewModel(
            initialItem: video,
            videos: [video],
            playbackStore: StubVideoPlaybackStore(),
            resolver: StubMediaSourceResolver(),
            remoteCommandBridge: StubRemoteCommandBridge(),
            uptimeProvider: { clock.now }
        )
    }

    private func makeTestVideoItem() -> MediaSourceItem {
        MediaSourceItem(
            id: "v_seek",
            name: "sample.mp4",
            path: "sample.mp4",
            type: .video,
            localURL: URL(fileURLWithPath: "/tmp/sample.mp4")
        )
    }
}
