//
//  VideoSeekCoordinator.swift
//  fichier
//

import AVFoundation
import Observation
import FichierKit

/// Coordinates responsive live scrubbing and exact frame seeking for `VideoPlayerController`.
///
/// ### Algorithmic Details & Seek Optimization
/// Rapid timeline scrubbing across remote network video presents distinct performance challenges:
/// 1. **Dynamic Seek Tolerances**: For small continuous finger drags (<1.0s), uses a tight tolerance of `0.5s`
///    for responsive keyframe updates; for moderate jumps (<5.0s), relaxes to `1.5s`; for large jumps, uses
///    `.positiveInfinity` to jump instantly to the nearest sync keyframe without decoding inter-frames.
/// 2. **Stationary Exact Seeking**: When finger dragging pauses for `250ms`, automatically promotes the preview
///    to an exact-frame zero-tolerance seek (`toleranceBefore: .zero, toleranceAfter: .zero`).
/// 3. **Generation Counter Invalidation**: Increments `seekGeneration` on every seek dispatch to ensure asynchronous
///    completions from earlier requests never overwrite later user seek targets.
/// 4. **Watchdog Timer**: Implements a 2.5-second watchdog task during `finishSeeking` that guarantees playback
///    resumes if AVPlayer's completion handler stalls due to network buffering.
@Observable
@MainActor
public final class VideoSeekCoordinator {
    /// Indicates whether timeline bar dragging is currently active.
    public var isScrubbingTimeline: Bool = false
    
    /// Indicates whether interactive horizontal drag gesture scrubbing is active.
    public var isScrubbingWithGesture: Bool = false
    
    /// Indicates whether an asynchronous seek request is actively in flight.
    public var isSeekingFrame: Bool = false
    
    /// Indicates whether the final completion seek is executing.
    public var isFinishingSeek: Bool = false
    
    /// Playback timestamp in seconds when gesture scrubbing originated.
    public var initialScrubTime: Double = 0
    
    /// Records whether video was actively playing prior to scrub initiation to resume automatically on release.
    public var wasPlayingBeforeScrub: Bool = false
    
    /// Queued seek timestamp awaiting throttle window completion.
    public var pendingSeekSeconds: Double?
    
    /// Timestamp of the most recent seek dispatch.
    public var lastSeekTime: Date = Date.distantPast
    
    /// Timestamp target in seconds of the most recent seek dispatch.
    public var lastSeekTargetSeconds: Double = 0
    
    /// Monotonically increasing generation number distinguishing active from obsolete seek operations.
    public var seekGeneration: Int = 0
    
    private var stationarySeekTask: Task<Void, Never>?
    private var throttleSeekTask: Task<Void, Never>?
    private var seekWatchdogTask: Task<Void, Never>?
    
    /// Designated public initializer.
    public init() {}
    
    /// Indicates whether any form of user scrubbing is currently active.
    public var isScrubbing: Bool {
        isScrubbingTimeline || isScrubbingWithGesture
    }
    
    /// Initiates timeline slider scrubbing, pausing playback if necessary across native or extended engines.
    public func startTimelineScrubbing(
        currentPlaybackSeconds: Double,
        isPlaying: Bool,
        player: AVPlayer? = nil,
        engine: (any PlayerEngine)? = nil
    ) {
        guard !isScrubbingTimeline else { return }
        isScrubbingTimeline = true
        lastSeekTargetSeconds = currentPlaybackSeconds
        let isPlayerActive = player != nil && player?.timeControlStatus != .paused
        let isEngineActive = engine?.isPlaying == true
        wasPlayingBeforeScrub = isPlayerActive || isEngineActive || isPlaying
        if wasPlayingBeforeScrub {
            engine?.pause()
            player?.pause()
        }
    }
    
    /// Concludes timeline slider scrubbing.
    public func endTimelineScrubbing() {
        isScrubbingTimeline = false
    }
    
    /// Initiates full-screen gesture scrubbing, pausing playback if necessary.
    public func startGestureScrubbing(currentPlaybackSeconds: Double, isPlaying: Bool, engine: (any PlayerEngine)?) {
        guard !isScrubbingWithGesture else { return }
        isScrubbingWithGesture = true
        lastSeekTargetSeconds = currentPlaybackSeconds
        wasPlayingBeforeScrub = (engine?.isPlaying == true) || isPlaying
        if wasPlayingBeforeScrub {
            engine?.pause()
        }
        initialScrubTime = currentPlaybackSeconds
    }
    
    /// Backward-compatible overload delegating to player or engine.
    public func startGestureScrubbing(currentPlaybackSeconds: Double, isPlaying: Bool, player: AVPlayer?) {
        guard !isScrubbingWithGesture else { return }
        isScrubbingWithGesture = true
        lastSeekTargetSeconds = currentPlaybackSeconds
        wasPlayingBeforeScrub = (player != nil && player?.timeControlStatus != .paused) || isPlaying
        if wasPlayingBeforeScrub {
            player?.pause()
        }
        initialScrubTime = currentPlaybackSeconds
    }
    
    /// Concludes full-screen gesture scrubbing.
    public func endGestureScrubbing() {
        isScrubbingWithGesture = false
    }
    
    /// Determines appropriate tolerance bounds based on scrub distance delta.
    public func liveSeekTolerance(for targetSeconds: Double) -> CMTime {
        let delta = abs(targetSeconds - lastSeekTargetSeconds)
        if delta < 1.0 {
            return CMTime(seconds: 0.5, preferredTimescale: 600)
        } else if delta < 5.0 {
            return CMTime(seconds: 1.5, preferredTimescale: 600)
        } else {
            return .positiveInfinity
        }
    }
    
    /// Submits a request for live frame seeking with an abstract player engine.
    public func requestLiveFrameSeek(to targetSeconds: Double, engine: (any PlayerEngine)?) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSeekTime)
        
        stationarySeekTask?.cancel()
        stationarySeekTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self.performStationaryExactSeek(to: targetSeconds, engine: engine)
        }
        
        if isSeekingFrame && elapsed < 0.12 {
            pendingSeekSeconds = targetSeconds
            return
        }
        
        let minInterval: TimeInterval = 0.10
        if elapsed < minInterval {
            pendingSeekSeconds = targetSeconds
            if throttleSeekTask == nil {
                let remaining = max(0.01, minInterval - elapsed)
                throttleSeekTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
                    guard !Task.isCancelled else { return }
                    self.throttleSeekTask = nil
                    if let next = self.pendingSeekSeconds {
                        self.pendingSeekSeconds = nil
                        self.executeLiveSeek(to: next, tolerance: self.liveSeekTolerance(for: next), engine: engine)
                    }
                }
            }
            return
        }
        
        executeLiveSeek(to: targetSeconds, tolerance: liveSeekTolerance(for: targetSeconds), engine: engine)
    }
    
    /// Dispatches an immediate seek operation to the engine with specified tolerance.
    public func executeLiveSeek(to targetSeconds: Double, tolerance: CMTime, engine: (any PlayerEngine)?) {
        guard let engine = engine else { return }
        throttleSeekTask?.cancel()
        throttleSeekTask = nil
        seekWatchdogTask?.cancel()
        seekWatchdogTask = nil
        
        seekGeneration += 1
        let thisGeneration = seekGeneration
        isSeekingFrame = true
        lastSeekTime = Date()
        lastSeekTargetSeconds = targetSeconds
        
        let tolSeconds = tolerance.isPositiveInfinity ? Double.infinity : tolerance.seconds
        engine.seek(to: targetSeconds, toleranceBefore: tolSeconds, toleranceAfter: tolSeconds) { _ in
            Task { @MainActor in
                guard thisGeneration == self.seekGeneration else { return }
                self.isSeekingFrame = false
                if let nextTarget = self.pendingSeekSeconds {
                    self.pendingSeekSeconds = nil
                    self.executeLiveSeek(to: nextTarget, tolerance: self.liveSeekTolerance(for: nextTarget), engine: engine)
                }
            }
        }
    }
    
    /// Upgrades the active preview to an exact frame seek when scrubbing motion pauses for 250ms.
    public func performStationaryExactSeek(to targetSeconds: Double, engine: (any PlayerEngine)?) {
        guard let engine = engine else { return }
        throttleSeekTask?.cancel()
        throttleSeekTask = nil
        seekWatchdogTask?.cancel()
        seekWatchdogTask = nil
        pendingSeekSeconds = nil
        
        seekGeneration += 1
        let thisGeneration = seekGeneration
        isSeekingFrame = true
        lastSeekTime = Date()
        lastSeekTargetSeconds = targetSeconds
        
        engine.seek(to: targetSeconds, toleranceBefore: 0.0, toleranceAfter: 0.0) { _ in
            Task { @MainActor in
                guard thisGeneration == self.seekGeneration else { return }
                self.isSeekingFrame = false
                if let nextTarget = self.pendingSeekSeconds {
                    self.pendingSeekSeconds = nil
                    self.executeLiveSeek(to: nextTarget, tolerance: self.liveSeekTolerance(for: nextTarget), engine: engine)
                }
            }
        }
    }
    
    /// Concludes user scrubbing on an abstract engine, executing a final seek and resuming playback if desired.
    public func finishSeeking(
        at targetSeconds: Double,
        resumePlaying: Bool,
        engine: (any PlayerEngine)?,
        onBuffering: (@MainActor @Sendable (Bool) -> Void)? = nil,
        onComplete: (@MainActor @Sendable () -> Void)? = nil
    ) {
        stationarySeekTask?.cancel()
        stationarySeekTask = nil
        throttleSeekTask?.cancel()
        throttleSeekTask = nil
        pendingSeekSeconds = nil
        isSeekingFrame = false
        seekWatchdogTask?.cancel()
        seekWatchdogTask = nil
        
        seekGeneration += 1
        let thisGeneration = seekGeneration
        
        guard let engine = engine else { return }
        let tolerance: Double = resumePlaying ? 1.0 : 0.0
        
        if resumePlaying {
            isFinishingSeek = true
            engine.play()
            onBuffering?(true)
        }
        
        seekWatchdogTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, thisGeneration == self.seekGeneration else { return }
            if resumePlaying && !engine.isPlaying {
                engine.play()
            }
        }
        
        engine.seek(to: targetSeconds, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in
            Task { @MainActor in
                guard thisGeneration == self.seekGeneration else { return }
                self.seekWatchdogTask?.cancel()
                self.seekWatchdogTask = nil
                self.isFinishingSeek = false
                
                if resumePlaying && !engine.isPlaying {
                    engine.play()
                }
                
                onBuffering?(false)
                onComplete?()
            }
        }
    }
    
    /// Submits a request for live frame seeking, throttling dispatches to a minimum 100ms interval.
    public func requestLiveFrameSeek(to targetSeconds: Double, player: AVPlayer?) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSeekTime)
        
        stationarySeekTask?.cancel()
        stationarySeekTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self.performStationaryExactSeek(to: targetSeconds, player: player)
        }
        
        if isSeekingFrame && elapsed < 0.12 {
            pendingSeekSeconds = targetSeconds
            return
        }
        
        let minInterval: TimeInterval = 0.10
        if elapsed < minInterval {
            pendingSeekSeconds = targetSeconds
            if throttleSeekTask == nil {
                let remaining = max(0.01, minInterval - elapsed)
                throttleSeekTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
                    guard !Task.isCancelled else { return }
                    self.throttleSeekTask = nil
                    if let next = self.pendingSeekSeconds {
                        self.pendingSeekSeconds = nil
                        self.executeLiveSeek(to: next, tolerance: self.liveSeekTolerance(for: next), player: player)
                    }
                }
            }
            return
        }
        
        executeLiveSeek(to: targetSeconds, tolerance: liveSeekTolerance(for: targetSeconds), player: player)
    }
    
    /// Dispatches an immediate seek operation to the player with specified tolerance.
    public func executeLiveSeek(to targetSeconds: Double, tolerance: CMTime, player: AVPlayer?) {
        guard let player = player else { return }
        throttleSeekTask?.cancel()
        throttleSeekTask = nil
        seekWatchdogTask?.cancel()
        seekWatchdogTask = nil
        
        seekGeneration += 1
        let thisGeneration = seekGeneration
        isSeekingFrame = true
        lastSeekTime = Date()
        lastSeekTargetSeconds = targetSeconds
        
        let targetCM = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: targetCM, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in
            Task { @MainActor in
                guard thisGeneration == self.seekGeneration else { return }
                self.isSeekingFrame = false
                if let nextTarget = self.pendingSeekSeconds {
                    self.pendingSeekSeconds = nil
                    self.executeLiveSeek(to: nextTarget, tolerance: self.liveSeekTolerance(for: nextTarget), player: player)
                }
            }
        }
    }
    
    /// Upgrades the active preview to an exact frame seek when scrubbing motion pauses for 250ms.
    public func performStationaryExactSeek(to targetSeconds: Double, player: AVPlayer?) {
        guard let player = player else { return }
        throttleSeekTask?.cancel()
        throttleSeekTask = nil
        seekWatchdogTask?.cancel()
        seekWatchdogTask = nil
        pendingSeekSeconds = nil
        
        seekGeneration += 1
        let thisGeneration = seekGeneration
        isSeekingFrame = true
        lastSeekTime = Date()
        lastSeekTargetSeconds = targetSeconds
        
        let targetCM = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: targetCM, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                guard thisGeneration == self.seekGeneration else { return }
                self.isSeekingFrame = false
                if let nextTarget = self.pendingSeekSeconds {
                    self.pendingSeekSeconds = nil
                    self.executeLiveSeek(to: nextTarget, tolerance: self.liveSeekTolerance(for: nextTarget), player: player)
                }
            }
        }
    }
    
    /// Concludes user scrubbing, executing a final seek and resuming playback if desired.
    public func finishSeeking(
        at targetSeconds: Double,
        resumePlaying: Bool,
        player: AVPlayer?,
        onBuffering: (@MainActor @Sendable (Bool) -> Void)? = nil,
        onComplete: (@MainActor @Sendable () -> Void)? = nil
    ) {
        stationarySeekTask?.cancel()
        stationarySeekTask = nil
        throttleSeekTask?.cancel()
        throttleSeekTask = nil
        pendingSeekSeconds = nil
        isSeekingFrame = false
        seekWatchdogTask?.cancel()
        seekWatchdogTask = nil
        
        seekGeneration += 1
        let thisGeneration = seekGeneration
        
        guard let player = player else { return }
        let targetCM = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        
        let tolerance: CMTime = resumePlaying ? CMTime(seconds: 1.0, preferredTimescale: 600) : .zero
        
        if resumePlaying {
            isFinishingSeek = true
            player.play()
            onBuffering?(true)
        }
        
        seekWatchdogTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, thisGeneration == self.seekGeneration else { return }
            if resumePlaying && player.timeControlStatus != .playing {
                player.play()
            }
        }
        
        player.seek(to: targetCM, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in
            Task { @MainActor in
                guard thisGeneration == self.seekGeneration else { return }
                self.seekWatchdogTask?.cancel()
                self.seekWatchdogTask = nil
                self.isFinishingSeek = false
                
                if resumePlaying {
                    if player.timeControlStatus == .paused {
                        player.play()
                    }
                }
                
                if player.timeControlStatus == .playing || player.currentItem?.isPlaybackLikelyToKeepUp == true {
                    onBuffering?(false)
                }
                onComplete?()
            }
        }
    }
    
    /// Resets all scrubbing state, cancelling in-flight throttle and watchdog tasks.
    public func reset() {
        stationarySeekTask?.cancel()
        stationarySeekTask = nil
        throttleSeekTask?.cancel()
        throttleSeekTask = nil
        seekWatchdogTask?.cancel()
        seekWatchdogTask = nil
        isScrubbingTimeline = false
        isScrubbingWithGesture = false
        isSeekingFrame = false
        isFinishingSeek = false
        pendingSeekSeconds = nil
        seekGeneration += 1
    }
}
