//
//  VideoPlayerController+LifecycleAndHUD.swift
//  fichier
//

import SwiftUI
import AVKit
import Wappn
import FichierKit

@MainActor
extension VideoPlayerController {
    // MARK: - HUD & Resume Banner

    /// Displays a temporary banner notifying the user that playback resumed from a saved timestamp.
    public func showResumeBanner(at savedSeconds: Double) {
        resumeBannerTask?.cancel()
        withAnimation(.easeInOut(duration: 0.3)) {
            resumedToastMessage = String(localized: .Strings.videoPlayerResumeToast(formatSeconds(savedSeconds)))
        }
        resumeBannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8.0))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                resumedToastMessage = nil
            }
        }
    }

    /// Formats a time in seconds into a standard digital clock string (e.g. "1:23" or "1:02:45").
    public func formatSeconds(_ totalSeconds: Double) -> String {
        MediaFormatHelper.formatTimestamp(totalSeconds, zeroPaddedHours: false, zeroPaddedMinutes: false)
    }

    /// Schedules automatic fading of HUD overlay controls after a period of user inactivity.
    ///
    /// - Parameter delay: Delay in seconds (defaults to 3.5s).
    public func scheduleControlsAutoHide(delay: Double = 3.5) {
        let isPlaying = (playbackState.isPlaying || isEnginePlaying)
        guard showControls && isPlaying && !seekCoordinator.isScrubbing else {
            hideControlsTask?.cancel()
            hideControlsTask = nil
            return
        }
        hideControlsTask?.cancel()
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                self.showControls = false
            }
        }
    }

    /// Cancels the auto-hide timer, keeping controls visible.
    public func cancelAutoHideTimer() {
        hideControlsTask?.cancel()
        hideControlsTask = nil
    }

    /// Resets the auto-hide timer if controls are currently displayed and playing.
    public func resetAutoHideTimer() {
        if showControls && (playbackState.isPlaying || isEnginePlaying) {
            scheduleControlsAutoHide()
        }
    }

    /// Toggles the visibility of overlay HUD controls.
    public func toggleControls() {
        guard !seekCoordinator.isScrubbing else { return }
        let now = Date()
        guard now.timeIntervalSince(lastControlsToggleTime) > 0.25 else { return }
        lastControlsToggleTime = now
        withAnimation(.easeInOut(duration: 0.35)) {
            showControls.toggle()
        }
        if showControls {
            scheduleControlsAutoHide()
        } else {
            cancelAutoHideTimer()
        }
    }

    /// Action handler for two-finger tap gestures, toggling play and pause with haptic feedback.
    public func handleTwoFingerTap() {
        AppHapticFeedback.medium()
        togglePlayPause()
    }

    // MARK: - View & Scene Lifecycle

    /// Clears the disappearance flag when the player view appears or restores from PiP.
    public func handleViewAppear() {
        hasDisappeared = false
    }

    /// Defers teardown while PiP is active and tears down immediately otherwise.
    public func handleViewDisappear() {
        hasDisappeared = true
        guard !isPiPActive else { return }
        tearDownPlayer(deactivateAudioSession: true)
    }

    /// Centralized completion handler invoked when playback reaches the end timestamp.
    public func handlePlaybackCompletion() {
        let targetItem = currentlyLoadedItem ?? currentItem

        didRestorePlaybackPosition = false
        restoredFromSeconds = nil

        if totalDurationSeconds > 0 {
            currentPlaybackSeconds = totalDurationSeconds
        }

        if totalDurationSeconds >= 2.0 && currentPlaybackSeconds >= totalDurationSeconds * 0.9 {
            VideoPlaybackStore.shared.markFinished(for: targetItem, duration: totalDurationSeconds)
        }

        playNextVideo()
    }

    /// Notification handler invoked when the active player item reaches its end timestamp.
    public func handleItemDidPlayToEndTime(_ notification: Notification) {
        guard nativeEngine == nil,
              let item = notification.object as? AVPlayerItem,
              let current = player?.currentItem,
              item == current else { return }
        handlePlaybackCompletion()
    }

    /// Notification handler invoked when playback fails prematurely before reaching the end.
    public func handleItemFailedToPlayToEndTime(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem,
              let current = player?.currentItem,
              item == current else { return }
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            presentPlaybackError(error.localizedDescription)
        }
    }

    /// Saves current playback progress when the application enters the background scene phase.
    public func handleScenePhaseBackground() {
        if let loadedItem = currentlyLoadedItem {
            let secs: Double
            let dur: Double
            if let currentEngine = engine {
                secs = currentEngine.currentTime
                let engineDur = currentEngine.duration
                dur = engineDur > 0 ? engineDur : totalDurationSeconds
            } else if let p = player {
                secs = p.currentTime().seconds
                dur = p.currentItem?.duration.seconds ?? totalDurationSeconds
            } else {
                secs = currentPlaybackSeconds
                dur = totalDurationSeconds
            }

            let isNearEnd = dur > 0 && (secs >= dur - 4.0 || secs >= dur * 0.90)
            if secs.isFinite && !secs.isNaN && dur.isFinite && !dur.isNaN && secs >= 2.0 && !isNearEnd {
                VideoPlaybackStore.shared.savePosition(secs, duration: dur, for: loadedItem)
            }
        }
        VideoPlaybackStore.shared.flush()
        #if !os(tvOS)
        if engineKind == .extended,
           let extendedEngine,
           !isPiPActive,
           extendedEngine.isPlaying {
            extendedEngine.startPiP()
        }
        #endif
    }

    /// Checks player health and recovers active SMB streams when the application enters the foreground.
    public func handleScenePhaseActive() {
        guard let current = currentlyLoadedItem else { return }

        // If native player item failed due to background socket teardown, re-arm the player
        if let currentItem = player?.currentItem, currentItem.status == .failed {
            let lastSeconds = player?.currentTime().seconds
            let targetPosition: Double
            if let lastSeconds, lastSeconds.isFinite, lastSeconds > 0 {
                targetPosition = lastSeconds
            } else {
                targetPosition = currentPlaybackSeconds
            }

            if targetPosition.isFinite && targetPosition > 0 {
                VideoPlaybackStore.shared.savePosition(targetPosition, duration: totalDurationSeconds, for: current)
            }

            logw("AVPlayerItem failed while in background for \(current.name); reloading stream...")
            setupPlayer(for: current)
        }
    }
}
