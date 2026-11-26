//
//  VideoPlayerController+PlaybackControls.swift
//  fichier
//

import SwiftUI
import AVKit
import FichierKit

@MainActor
extension VideoPlayerController {
    // MARK: - Track, Volume & Playback Rate

    /// Toggles subtitle track selection between Off and the primary available track.
    public func toggleSubtitles() {
        trackManager.toggleSubtitles(in: player?.currentItem, engine: engineKind == .extended ? extendedEngine : nil)
    }

    /// Selects the specified subtitle track option.
    public func selectSubtitle(option: VideoTrackOption) {
        trackManager.selectSubtitle(option: option, in: player?.currentItem, engine: engineKind == .extended ? extendedEngine : nil)
    }

    /// Selects the specified audio track option.
    public func selectAudio(option: VideoTrackOption) {
        trackManager.selectAudio(option: option, in: player?.currentItem, engine: engineKind == .extended ? extendedEngine : nil)
    }

    /// Sets normalized volume across active player engine and AVPlayer instance.
    public func setVolume(_ newVolume: Double) {
        self.volume = max(0.0, min(1.0, newVolume))
        self.engine?.volume = self.volume
        if self.engine == nil {
            self.player?.volume = Float(self.volume)
        }
    }

    /// Sets muted state across active player engine and AVPlayer instance.
    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        self.engine?.isMuted = muted
        if self.engine == nil {
            self.player?.isMuted = muted
        }
    }

    /// Configures playback rate multiplier across active manager and engines.
    public func setPlaybackRate(_ rate: VideoPlaybackRate) {
        trackManager.setPlaybackRate(rate, for: self.engine)
        if self.engine == nil, let player = self.player {
            trackManager.setPlaybackRate(rate, for: player)
        }
    }

    /// Toggles the audio output between muted and unmuted.
    public func toggleMute() {
        setMuted(!isMuted)
        withAnimation {
            showControls = true
        }
        scheduleControlsAutoHide()
    }

    /// Adjusts the player volume by a given delta offset.
    ///
    /// - Parameter delta: Normalized volume delta (e.g. `+0.1` or `-0.1`).
    public func adjustVolume(by delta: Double) {
        let newVol = min(max(0.0, volume + delta), 1.0)
        setMuted(false)
        setVolume(newVol)
        withAnimation {
            showControls = true
        }
        scheduleControlsAutoHide()
    }

    // MARK: - Transport & Seeking

    /// Toggles between playing and paused states, wrapping to beginning if reaching the end.
    public func togglePlayPause() {
        if isAtEnd {
            seekTo(0, resumePlaying: true)
            currentPlaybackSeconds = 0
            return
        }

        let isPlayerPlaying = player != nil && player?.timeControlStatus != .paused
        let currentlyPlaying = engine?.isPlaying ?? (isPlayerPlaying || (player == nil && playbackState.isPlaying))
        if currentlyPlaying {
            pause()
            withAnimation(.easeInOut(duration: 0.35)) {
                showControls = true
            }
        } else {
            play()
        }
    }

    /// Starts or resumes playback.
    public func play() {
        if let engine {
            engine.play()
        } else if let player, player.timeControlStatus == .paused {
            player.play()
        }
        playbackState = .playing
        scheduleControlsAutoHide()
    }

    /// Pauses active playback and retains control bar visibility.
    public func pause() {
        if let engine {
            engine.pause()
        } else if let player, player.timeControlStatus != .paused {
            player.pause()
        }
        playbackState = .paused
        cancelAutoHideTimer()
    }

    /// Performs an exact seek to a specific timestamp in seconds.
    public func seekTo(_ targetSeconds: Double, resumePlaying: Bool = false) {
        finishSeeking(at: targetSeconds, resumePlaying: resumePlaying)
    }

    /// Jumps directly to an absolute timestamp (e.g., from a chapter marker or quick-jump preset).
    ///
    /// - Parameter targetSeconds: Target timestamp in seconds.
    public func jumpToTime(_ targetSeconds: Double) {
        let dur = totalDurationSeconds > 0 ? totalDurationSeconds : (player?.currentItem?.duration.seconds ?? 0)
        let clamped: Double
        if dur.isFinite, !dur.isNaN, dur > 0 {
            clamped = max(0, min(dur, targetSeconds))
        } else {
            clamped = max(0, targetSeconds)
        }
        didRestorePlaybackPosition = false
        restoredFromSeconds = nil
        currentPlaybackSeconds = clamped

        if engineKind == .extended, let extendedEngine {
            extendedEngine.seek(to: clamped, precision: .fast)
        } else {
            let isPlayerPlaying = player != nil && player?.timeControlStatus != .paused
            let resume = (engine?.isPlaying ?? isPlayerPlaying) || playbackState.isPlaying
            finishSeeking(at: clamped, resumePlaying: resume)
        }

        if let item = currentlyLoadedItem,
           clamped >= 2.0,
           dur.isFinite, !dur.isNaN, dur > 0 {
            VideoPlaybackStore.shared.savePosition(clamped, duration: dur, for: item)
        }
        withAnimation {
            showControls = true
        }
        scheduleControlsAutoHide()
    }

    /// Jumps forward or backward relative to the current playback position.
    ///
    /// - Parameter deltaSeconds: Offset in seconds (e.g. +10 or -10).
    public func seekRelative(_ deltaSeconds: Double) {
        if engineKind == .extended, let extendedEngine {
            didRestorePlaybackPosition = false
            restoredFromSeconds = nil
            extendedEngine.jump(by: deltaSeconds)
            currentPlaybackSeconds = extendedEngine.currentTime
            withAnimation {
                showControls = true
            }
            scheduleControlsAutoHide()
            return
        }

        let current = currentPlaybackSeconds
        let dur = totalDurationSeconds > 0 ? totalDurationSeconds : (player?.currentItem?.duration.seconds ?? 0)
        let maxLimit = dur > 0 ? dur : max(current + deltaSeconds, 0)
        let newTarget = min(max(0, current + deltaSeconds), maxLimit)
        let isPlayerPlaying = player != nil && player?.timeControlStatus != .paused
        let resume = (engine?.isPlaying ?? isPlayerPlaying) || playbackState.isPlaying
        seekTo(newTarget, resumePlaying: resume)
        withAnimation {
            showControls = true
        }
        scheduleControlsAutoHide()
    }

    /// Executes the final seek when the user releases timeline or gesture scrubbing.
    public func finishSeeking(at targetSeconds: Double, resumePlaying: Bool) {
        didRestorePlaybackPosition = false
        restoredFromSeconds = nil
        currentPlaybackSeconds = targetSeconds

        if engineKind == .extended, let extendedEngine {
            extendedEngine.endScrubbing(at: targetSeconds)
            if resumePlaying && !extendedEngine.isPlaying {
                extendedEngine.play()
                playbackState = .playing
            }
            scheduleControlsAutoHide()
            return
        }

        if resumePlaying {
            playbackState = .buffering
            cancelAutoHideTimer()
        }

        if let engine {
            seekCoordinator.finishSeeking(
                at: targetSeconds,
                resumePlaying: resumePlaying,
                engine: engine,
                onBuffering: { [weak self] buffering in
                    guard let self else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if buffering {
                            self.cancelAutoHideTimer()
                            self.playbackState = .buffering
                        } else if self.engine?.isPlaying == true {
                            self.playbackState = .playing
                        }
                    }
                },
                onComplete: { [weak self] in
                    guard let self else { return }
                    if resumePlaying {
                        self.playbackState = .playing
                    }
                    self.scheduleControlsAutoHide()
                }
            )
        } else {
            seekCoordinator.finishSeeking(
                at: targetSeconds,
                resumePlaying: resumePlaying,
                player: player,
                onBuffering: { [weak self] buffering in
                    guard let self else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if buffering {
                            self.cancelAutoHideTimer()
                            self.playbackState = .buffering
                        } else if self.player?.timeControlStatus == .playing {
                            self.playbackState = .playing
                        }
                    }
                },
                onComplete: { [weak self] in
                    guard let self else { return }
                    if resumePlaying {
                        self.playbackState = .playing
                    }
                    self.scheduleControlsAutoHide()
                }
            )
        }
    }

    /// Callback from timeline scrubber when the user finishes dragging.
    public func onTimelineSeek(targetSeconds: Double) {
        if engineKind == .extended, let extendedEngine {
            didRestorePlaybackPosition = false
            restoredFromSeconds = nil
            currentPlaybackSeconds = targetSeconds
            extendedEngine.endScrubbing(at: targetSeconds)
            scheduleControlsAutoHide()
            return
        }
        finishSeeking(at: targetSeconds, resumePlaying: seekCoordinator.wasPlayingBeforeScrub)
    }

    /// Callback from timeline scrubber as the user actively drags their finger.
    public func onTimelineScrubbing(targetSeconds: Double) {
        currentPlaybackSeconds = targetSeconds
        if engineKind == .extended, let extendedEngine {
            extendedEngine.scrub(to: targetSeconds)
            return
        }
        if let engine {
            seekCoordinator.requestLiveFrameSeek(to: targetSeconds, engine: engine)
        } else {
            seekCoordinator.requestLiveFrameSeek(to: targetSeconds, player: player)
        }
    }

    /// Callback tracking changes in timeline scrubbing active state.
    public func onTimelineScrubStateChanged(isScrubbing: Bool) {
        if engineKind == .extended, let extendedEngine {
            if isScrubbing {
                hideControlsTask?.cancel()
            } else {
                if extendedEngine.isScrubbing {
                    extendedEngine.endScrubbing(at: currentPlaybackSeconds)
                }
                scheduleControlsAutoHide()
            }
            return
        }
        if isScrubbing {
            guard !seekCoordinator.isScrubbingTimeline else { return }
            seekCoordinator.startTimelineScrubbing(
                currentPlaybackSeconds: currentPlaybackSeconds,
                isPlaying: playbackState.isPlaying,
                player: player,
                engine: engine
            )
            if seekCoordinator.wasPlayingBeforeScrub {
                playbackState = .paused
            }
            hideControlsTask?.cancel()
        } else {
            seekCoordinator.endTimelineScrubbing()
            scheduleControlsAutoHide()
        }
    }

    // MARK: - Queue & Export Actions

    /// Navigates to the next video in the queue with cyclic wrapping.
    public func goToNext() {
        guard !videos.isEmpty else { return }
        let nextIndex = (currentIndex + 1) % videos.count
        withAnimation(.easeInOut(duration: 0.3)) {
            currentItem = videos[nextIndex]
        }
    }

    /// Advances to the next video upon playback reaching the end (does not loop to start).
    public func playNextVideo() {
        guard videos.count > 1 else {
            engine?.pause()
            player?.pause()
            playbackState = .paused
            withAnimation(.easeInOut(duration: 0.35)) {
                showControls = true
            }
            cancelAutoHideTimer()
            return
        }
        let nextIndex = currentIndex + 1
        if nextIndex < videos.count {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentItem = videos[nextIndex]
            }
        } else {
            engine?.pause()
            player?.pause()
            playbackState = .paused
            withAnimation(.easeInOut(duration: 0.35)) {
                showControls = true
            }
            cancelAutoHideTimer()
        }
    }

    /// Navigates to the previous video in the queue with cyclic wrapping.
    public func goToPrevious() {
        guard !videos.isEmpty else { return }
        let prevIndex = (currentIndex - 1 + videos.count) % videos.count
        withAnimation(.easeInOut(duration: 0.3)) {
            currentItem = videos[prevIndex]
        }
    }

    /// Downloads or copies the current video file into the system Photos library.
    public func saveToCameraRoll() {
        cameraRollExporter.saveToCameraRoll(
            item: currentItem,
            manager: manager
        ) { [weak self] localURL in
            self?.shareableVideoURL = localURL
        }
    }

    #if !os(tvOS)
    /// Downloads the current video file and presents the system Files export picker.
    public func downloadToFiles() {
        cameraRollExporter.downloadToFiles(
            item: currentItem,
            manager: manager
        ) { [weak self] localURL in
            self?.shareableVideoURL = localURL
        }
    }
    #endif

    /// Restarts the video from `0:00` and purges any saved resume progress from persistent store.
    public func restartVideo() {
        guard engine != nil || player != nil else { return }
        let targetItem = currentlyLoadedItem ?? currentItem
        let shouldResume = playbackState.isPlaying || playbackState.isBuffering || isEnginePlaying
        didRestorePlaybackPosition = false
        restoredFromSeconds = nil
        resumeBannerTask?.cancel()
        seekTo(0, resumePlaying: shouldResume)
        currentPlaybackSeconds = 0
        VideoPlaybackStore.shared.clearPosition(for: targetItem)
        withAnimation {
            resumedToastMessage = nil
        }
    }
}
