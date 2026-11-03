//
//  VideoSeekCoordinator.swift
//  fichier
//

import AVFoundation
import Observation

@Observable
@MainActor
public final class VideoSeekCoordinator {
    public var isScrubbingTimeline: Bool = false
    public var isScrubbingWithGesture: Bool = false
    public var isSeekingFrame: Bool = false
    public var isFinishingSeek: Bool = false
    
    public var initialScrubTime: Double = 0
    public var wasPlayingBeforeScrub: Bool = false
    public var pendingSeekSeconds: Double? = nil
    public var lastSeekTime: Date = Date.distantPast
    public var lastSeekTargetSeconds: Double = 0
    public var seekGeneration: Int = 0
    
    private var stationarySeekTask: Task<Void, Never>?
    private var throttleSeekTask: Task<Void, Never>?
    private var seekWatchdogTask: Task<Void, Never>?
    
    public init() {}
    
    public var isScrubbing: Bool {
        isScrubbingTimeline || isScrubbingWithGesture
    }
    
    public func startTimelineScrubbing(currentPlaybackSeconds: Double, isPlaying: Bool, player: AVPlayer?) {
        guard !isScrubbingTimeline else { return }
        isScrubbingTimeline = true
        lastSeekTargetSeconds = currentPlaybackSeconds
        wasPlayingBeforeScrub = (player?.timeControlStatus != .paused) || isPlaying
        if wasPlayingBeforeScrub {
            player?.pause()
        }
    }
    
    public func endTimelineScrubbing() {
        isScrubbingTimeline = false
    }
    
    public func startGestureScrubbing(currentPlaybackSeconds: Double, isPlaying: Bool, player: AVPlayer?) {
        guard !isScrubbingWithGesture else { return }
        isScrubbingWithGesture = true
        lastSeekTargetSeconds = currentPlaybackSeconds
        wasPlayingBeforeScrub = (player?.timeControlStatus != .paused) || isPlaying
        if wasPlayingBeforeScrub {
            player?.pause()
        }
        initialScrubTime = currentPlaybackSeconds
    }
    
    public func endGestureScrubbing() {
        isScrubbingWithGesture = false
    }
    
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
    
    public func finishSeeking(
        at targetSeconds: Double,
        resumePlaying: Bool,
        player: AVPlayer?,
        onBuffering: ((Bool) -> Void)? = nil,
        onComplete: (() -> Void)? = nil
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
