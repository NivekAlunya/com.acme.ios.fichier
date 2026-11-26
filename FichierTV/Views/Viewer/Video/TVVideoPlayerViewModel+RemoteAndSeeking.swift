//
//  TVVideoPlayerViewModel+RemoteAndSeeking.swift
//  FichierTV
//

import SwiftUI
import FichierKit

@MainActor
extension TVVideoPlayerViewModel {
    // MARK: - Remote Navigation & Input Handling

    /// Reveals the HUD overlay if hidden and resets auto-hide timing.
    public func revealOverlay() {
        resetInactivityTimer()
        if let hold = remoteSeekCoordinator.activeRemoteSeekHold {
            cancelRemoteSeek(isForward: hold.isForward, source: hold.source)
        }
        guard !showOverlay else { return }
        withAnimation(.snappy) {
            showOverlay = true
        }
    }

    /// Synchronizes ViewModel row/button focus tracking with native tvOS Focus Engine changes.
    public func syncFocusTarget(_ target: TVVideoOverlayFocusTarget?) {
        resetInactivityTimer()
        guard let target else { return }

        if target != .progress && isScrubbing {
            cancelScrub()
        }

        switch target {
        case .progress:
            activeFocusRow = .progress
        case .previous:
            activeFocusRow = .buttons
            activeFocusedButton = .previous
        case .playPause:
            activeFocusRow = .buttons
            activeFocusedButton = .playPause
        case .next:
            activeFocusRow = .buttons
            activeFocusedButton = .next
        case .switchEngine:
            activeFocusRow = .buttons
            activeFocusedButton = .switchEngine
        case .chapters:
            activeFocusRow = .buttons
            activeFocusedButton = .chapters
        case .tracks:
            activeFocusRow = .buttons
            activeFocusedButton = .tracks
        case .speed:
            activeFocusRow = .buttons
            activeFocusedButton = .speed
        case .pip:
            activeFocusRow = .buttons
            activeFocusedButton = .pip
        }
    }

    /// Steps accelerated scrubbing forward or backward when the progress scrubber has focus.
    public func stepScrub(forward: Bool) {
        activeFocusRow = .progress
        resetInactivityTimer()
        adjustScrub(forward: forward)
    }

    /// Applies continuous horizontal swipe deltas from the Siri Remote touchpad when the HUD scrubber has focus.
    public func updateSwipeScrub(translationDeltaX: Double, velocityX: Double, trackWidth: Double) {
        guard duration > 0 else { return }
        activeFocusRow = .progress
        resetInactivityTimer()

        let delta = TVRemoteSeekCalculator.swipeScrubDelta(
            translationDeltaX: translationDeltaX,
            velocityX: velocityX,
            trackWidth: trackWidth,
            totalDuration: duration
        )
        guard delta.isFinite && !delta.isNaN else { return }

        let baseTime = scrubbingTime ?? currentTime
        let clampedTarget = max(0, min(duration, baseTime + delta))
        isScrubbing = true
        scrubbingTime = clampedTarget
        requestSeekThumbnail(for: clampedTarget)
    }

    /// Completes an active touchpad swipe gesture while leaving the scrubbed timestamp parked until Select/Menu.
    public func finishSwipeScrubInteraction() {
        resetInactivityTimer()
    }

    /// Commits pending scrub seek when scrubbing, or toggles playback otherwise.
    public func activateScrubberSelect() {
        resetInactivityTimer()
        if isScrubbing {
            commitScrub()
        } else {
            togglePlayPause()
        }
    }

    /// Presents the Chapters & Quick Jump sheet while pausing overlay auto-hide.
    public func openChaptersMenu() {
        autoHideTask?.cancel()
        isShowingChaptersSheet = true
    }

    /// Jumps directly to a target chapter or quick-jump timestamp using fast keyframe seeking.
    public func jumpToTime(_ targetSeconds: Double) {
        guard targetSeconds.isFinite && !targetSeconds.isNaN else { return }
        let upperBound = duration > 0 ? duration : max(0, targetSeconds)
        let clamped = max(0, min(upperBound, targetSeconds))
        let delta = clamped - currentTime

        clearRemoteSeekState()
        cancelSeekThumbnails(clearState: true)

        let timestamp = uptimeProvider()
        commitRemoteSeek(to: clamped, at: timestamp)
        remoteSeekCoordinator.presentRemoteSeekPreview(
            TVRemoteSeekPreview(targetTime: clamped, deltaSeconds: delta, isHolding: false)
        )
    }

    /// Presents the Audio & Subtitles track selection sheet while pausing overlay auto-hide.
    public func openTracksMenu() {
        autoHideTask?.cancel()
        isShowingTracksSheet = true
    }

    /// Presents the Playback Speed selection sheet while pausing overlay auto-hide.
    public func openSpeedMenu() {
        autoHideTask?.cancel()
        isShowingSpeedSheet = true
    }

    /// Updates the playback speed multiplier across both native and extended playback engines.
    public func selectPlaybackRate(_ rate: TVVideoPlaybackRate) {
        resetInactivityTimer()
        playbackRate = rate
        nativeEngine.playbackRate = rate.rawValue
        extendedEngine.playbackRate = rate.rawValue
    }

    /// Processes directional D-pad input from the Siri Remote.
    public func handleDirectionalInput(direction: MoveCommandDirection) {
        resetInactivityTimer()

        // Section 6: First directional press only reveals hidden overlay
        guard showOverlay else {
            withAnimation(.snappy) {
                showOverlay = true
            }
            return
        }

        switch direction {
        case .up:
            activeFocusRow = .progress
        case .down:
            activeFocusRow = .buttons
        case .left:
            if activeFocusRow == .progress {
                adjustScrub(forward: false)
            } else {
                moveButtonFocus(forward: false)
            }
        case .right:
            if activeFocusRow == .progress {
                adjustScrub(forward: true)
            } else {
                moveButtonFocus(forward: true)
            }
        @unknown default:
            break
        }
    }

    /// Processes the Siri Remote Select button.
    public func handleSelect() {
        resetInactivityTimer()

        // Section 6: First Select press only reveals hidden overlay
        guard showOverlay else {
            withAnimation(.snappy) {
                showOverlay = true
            }
            return
        }

        if activeFocusRow == .progress && isScrubbing {
            commitScrub()
        } else if activeFocusRow == .buttons {
            activateFocusedButton()
        }
    }

    /// Multi-tiered Menu back button handler:
    /// 1. Cancel an active `<<`/`>>` remote hold without seeking
    /// 2. Cancel scrub if scrubbing
    /// 3. Hide overlay if visible
    /// 4. Returns `false` to permit `NavigationStack` pop
    public func handleMenuPress() -> Bool {
        resetInactivityTimer()

        if let hold = remoteSeekCoordinator.activeRemoteSeekHold, !hold.wasCancelledByMenu {
            remoteSeekCoordinator.cancelActiveRemoteSeekHoldByMenu()
            cancelSeekThumbnails(clearState: true)
            return true
        }

        if isScrubbing {
            cancelScrub()
            return true
        }

        if showOverlay {
            withAnimation(.snappy) {
                showOverlay = false
            }
            return true
        }

        return false
    }

    /// Begins tracking a `<<` / `>>` press-and-release seek gesture from Siri Remote or hardware remote commands.
    public func beginRemoteSeek(
        isForward: Bool,
        source: TVRemoteSeekSource,
        timestamp: TimeInterval? = nil
    ) {
        guard errorMessage == nil, !videos.isEmpty else { return }
        autoHideTask?.cancel()
        remoteSeekCoordinator.beginRemoteSeek(isForward: isForward, source: source, timestamp: timestamp)
    }

    /// Completes a `<<` / `>>` press gesture as a tap (`±15s`), double-tap within `0.50s` (`±60s`),
    /// or progressive hold multiplier seek (`>= 0.30s`).
    public func endRemoteSeek(
        isForward: Bool,
        source: TVRemoteSeekSource,
        timestamp: TimeInterval? = nil
    ) {
        remoteSeekCoordinator.endRemoteSeek(isForward: isForward, source: source, timestamp: timestamp)
    }

    /// Cancels an active press gesture without seeking playback (for example when UIKit cancels a press).
    public func cancelRemoteSeek(isForward: Bool, source: TVRemoteSeekSource) {
        remoteSeekCoordinator.cancelRemoteSeek(isForward: isForward, source: source)
    }

    /// Executes an immediate discrete `±15s` tap (upgrading to `±60s` total on a second tap within `0.50s`).
    public func triggerRemoteTapSkip(isForward: Bool, timestamp: TimeInterval? = nil) {
        guard errorMessage == nil, !videos.isEmpty else { return }
        remoteSeekCoordinator.triggerRemoteTapSkip(isForward: isForward, timestamp: timestamp)
    }

    /// Updates live preview state when an active hold has crossed the hold threshold (exposed for tests and 20 Hz loop).
    public func refreshActiveRemoteSeekPreview(at timestamp: TimeInterval? = nil) {
        remoteSeekCoordinator.refreshActiveRemoteSeekPreview(at: timestamp)
    }

    /// Starts or resumes playback cleanly.
    public func play() {
        resetInactivityTimer()
        activeEngine.play()
        playbackState = activeEngine.playbackState
        isPlaying = activeEngine.isPlaying
        publishNowPlaying(force: true)
    }

    /// Pauses playback cleanly.
    public func pause() {
        resetInactivityTimer()
        activeEngine.pause()
        playbackState = activeEngine.playbackState
        isPlaying = activeEngine.isPlaying
        saveCurrentProgressSnapshot()
        publishNowPlaying(force: true)
    }

    /// Handles hardware/Siri Remote Play/Pause presses while deduplicating potential dual MediaRemote delivery.
    public func handlePlayPauseCommand() {
        lastLocalPlayPauseUptime = uptimeProvider()
        togglePlayPause()
    }

    /// Toggles play / pause (always works regardless of overlay state).
    public func togglePlayPause() {
        resetInactivityTimer()
        activeEngine.togglePlayPause()
        playbackState = activeEngine.playbackState
        isPlaying = activeEngine.isPlaying
        if !isPlaying {
            saveCurrentProgressSnapshot()
        }
        publishNowPlaying(force: true)
    }

    /// Selects an audio track on the active playback engine.
    public func selectAudioTrack(_ track: PlayerAudioTrack) {
        resetInactivityTimer()
        activeEngine.selectAudioTrack(track)
        selectedAudioTrack = activeEngine.selectedAudioTrack
    }

    /// Selects a subtitle track (or `nil` to disable subtitles) on the active playback engine.
    public func selectSubtitleTrack(_ track: PlayerSubtitleTrack?) {
        resetInactivityTimer()
        activeEngine.selectSubtitleTrack(track)
        selectedSubtitleTrack = activeEngine.selectedSubtitleTrack
    }

    // MARK: - Scrubbing & Acceleration

    public func adjustScrub(forward: Bool) {
        remoteSeekCoordinator.adjustScrub(forward: forward)
    }

    public func commitScrub() {
        remoteSeekCoordinator.commitScrub()
    }

    public func cancelScrub() {
        remoteSeekCoordinator.cancelScrub()
    }

    // MARK: - Remote Seek Mechanics

    public func commitRemoteSeek(to targetTime: Double, at timestamp: TimeInterval) {
        activeEngine.seek(to: targetTime, precision: .fast)
        currentTime = targetTime
        remoteSeekCoordinator.recordCommittedSeek(target: targetTime, at: timestamp)
        saveCurrentProgressSnapshot()
        publishNowPlaying(force: true)
        resetInactivityTimer()
    }

    func clearRemoteSeekState() {
        remoteSeekCoordinator.reset()
    }

    // MARK: - Seek Frame Thumbnail Preview Worker

    public func requestSeekThumbnail(for targetTime: Double) {
        let targetURL = directSMBURL ?? resolvedMediaURL
        thumbnailCoordinator.requestSeekThumbnail(
            for: targetTime,
            duration: duration,
            assetKey: currentItem.id,
            targetURL: targetURL,
            engineKind: activeEngineKind,
            vlcOptions: vlcPlaybackOptions,
            activeTargetProvider: { [weak self] in
                self?.remoteSeekCoordinator.resolveActiveThumbnailTarget()
            }
        )
    }

    func cancelSeekThumbnails(clearState: Bool) {
        thumbnailCoordinator.cancelSeekThumbnails(clearState: clearState)
    }

    func resetCachedSeekThumbnails() {
        thumbnailCoordinator.reset(forAssetKey: nil)
    }

    func activateRemoteCommandBridgeIfNeeded() {
        guard !isRemoteCommandBridgeActive else { return }
        isRemoteCommandBridgeActive = true

        let callbacks = TVRemoteCommandCallbacks(
            onSeekBegan: { [weak self] isForward, uptime in
                self?.beginRemoteSeek(isForward: isForward, source: .hardwareMediaCommand, timestamp: uptime)
            },
            onSeekEnded: { [weak self] isForward, uptime in
                self?.endRemoteSeek(isForward: isForward, source: .hardwareMediaCommand, timestamp: uptime)
            },
            onTapSkip: { [weak self] isForward, uptime in
                self?.triggerRemoteTapSkip(isForward: isForward, timestamp: uptime)
            },
            onPlay: { [weak self] in
                self?.play()
            },
            onPause: { [weak self] in
                self?.pause()
            },
            onTogglePlayPause: { [weak self] uptime in
                guard let self else { return }
                if let lastLocal = self.lastLocalPlayPauseUptime, abs(uptime - lastLocal) < 0.08 {
                    return
                }
                self.togglePlayPause()
            }
        )
        remoteCommandBridge.activate(callbacks: callbacks)
    }

    func deactivateRemoteCommandBridge() {
        guard isRemoteCommandBridgeActive else { return }
        isRemoteCommandBridgeActive = false
        remoteCommandBridge.deactivate()
    }

    func publishNowPlaying(force: Bool) {
        guard isRemoteCommandBridgeActive else { return }
        if !force && abs(currentTime - lastPublishedNowPlayingTime) < 1.0 {
            return
        }
        lastPublishedNowPlayingTime = currentTime
        remoteCommandBridge.updateNowPlaying(
            title: currentItem.name,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    // MARK: - Button Row Navigation

    private func moveButtonFocus(forward: Bool) {
        switch activeFocusedButton {
        case .previous:
            if forward { activeFocusedButton = .playPause }
        case .playPause:
            activeFocusedButton = forward ? .next : .previous
        case .next:
            activeFocusedButton = forward ? .chapters : .playPause
        case .chapters:
            activeFocusedButton = forward ? .tracks : .next
        case .tracks:
            activeFocusedButton = forward ? .speed : .chapters
        case .speed:
            activeFocusedButton = forward ? (activeEngineKind == .native ? .pip : .switchEngine) : .tracks
        case .pip:
            activeFocusedButton = forward ? .switchEngine : .speed
        case .switchEngine:
            if !forward {
                activeFocusedButton = (activeEngineKind == .native) ? .pip : .speed
            }
        }
    }

    private func activateFocusedButton() {
        switch activeFocusedButton {
        case .previous:
            previousVideo()
        case .playPause:
            togglePlayPause()
        case .next:
            nextVideo()
        case .switchEngine:
            switchEngine()
        case .chapters:
            openChaptersMenu()
        case .tracks:
            openTracksMenu()
        case .speed:
            openSpeedMenu()
        case .pip:
            togglePiP()
        }
    }

    /// Toggles Picture-in-Picture presentation for the native playback engine on tvOS.
    public func togglePiP() {
        resetInactivityTimer()
        guard activeEngineKind == .native else { return }
        pipCoordinator.togglePiP()
    }

    public func nextVideo() {
        if currentIndex < videos.count - 1 {
            saveCurrentProgressSnapshot()
            currentIndex += 1
            loadCurrentVideo()
            scheduleLookaheadIfNeeded()
        } else if hasMoreSourcePages {
            loadMoreAndAdvance()
        }
    }

    public func previousVideo() {
        if currentIndex > 0 {
            saveCurrentProgressSnapshot()
            currentIndex -= 1
            loadCurrentVideo()
        }
    }
}
