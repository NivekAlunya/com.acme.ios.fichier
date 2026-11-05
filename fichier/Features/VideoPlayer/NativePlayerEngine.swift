//
//  NativePlayerEngine.swift
//  fichier
//

import AVFoundation
import Foundation

/// AVFoundation native playback engine implementation conforming to `VideoPlayerEngineProtocol`.
///
/// Wraps `AVPlayer` and `AVPlayerItem` for hardware-accelerated playback of standard Apple formats
/// (`.mp4`, `.mov`, `.m4v`, `.3gp`).
@MainActor
public final class NativePlayerEngine: NSObject, VideoPlayerEngineProtocol {
    public let engineKind: VideoEngineKind = .native
    
    /// Underlying AVFoundation player instance.
    public let avPlayer: AVPlayer
    
    private var timeObserverToken: Any?
    private var onTimeUpdate: (@MainActor @Sendable (Double) -> Void)?
    private var onDurationUpdate: (@MainActor @Sendable (Double) -> Void)?
    private var onStateUpdate: (@MainActor @Sendable (VideoPlaybackState) -> Void)?
    
    public var isPlaying: Bool {
        avPlayer.timeControlStatus == .playing || (avPlayer.rate > 0 && avPlayer.error == nil)
    }
    
    public var currentTimeSeconds: Double {
        let sec = avPlayer.currentTime().seconds
        return (sec.isFinite && !sec.isNaN) ? max(0, sec) : 0
    }
    
    public var durationSeconds: Double {
        guard let item = avPlayer.currentItem else { return 0 }
        let sec = item.duration.seconds
        return (sec.isFinite && !sec.isNaN && sec > 0) ? sec : 0
    }
    
    public var volume: Double {
        get { Double(avPlayer.volume) }
        set { avPlayer.volume = Float(max(0.0, min(1.0, newValue))) }
    }
    
    public var isMuted: Bool {
        get { avPlayer.isMuted }
        set { avPlayer.isMuted = newValue }
    }
    
    public var playbackRate: VideoPlaybackRate = .normal {
        didSet {
            if isPlaying {
                avPlayer.rate = playbackRate.rawValue
            }
        }
    }
    
    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - player: Preconfigured `AVPlayer` instance.
    ///   - onTimeUpdate: Callback invoked on periodic playback time ticks.
    ///   - onDurationUpdate: Callback invoked when duration is resolved.
    ///   - onStateUpdate: Callback invoked when playback state transitions.
    public init(
        player: AVPlayer,
        onTimeUpdate: (@MainActor @Sendable (Double) -> Void)? = nil,
        onDurationUpdate: (@MainActor @Sendable (Double) -> Void)? = nil,
        onStateUpdate: (@MainActor @Sendable (VideoPlaybackState) -> Void)? = nil
    ) {
        self.avPlayer = player
        self.onTimeUpdate = onTimeUpdate
        self.onDurationUpdate = onDurationUpdate
        self.onStateUpdate = onStateUpdate
        super.init()
        setupTimeObserver()
    }
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let sec = time.seconds
            if sec.isFinite && !sec.isNaN {
                self.onTimeUpdate?(max(0, sec))
            }
            let dur = self.durationSeconds
            if dur > 0 {
                self.onDurationUpdate?(dur)
            }
        }
    }
    
    public func play() {
        avPlayer.rate = playbackRate.rawValue
    }
    
    public func pause() {
        avPlayer.pause()
    }
    
    public func seek(
        to seconds: Double,
        toleranceBefore: Double,
        toleranceAfter: Double,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolBefore = CMTime(seconds: toleranceBefore, preferredTimescale: 600)
        let tolAfter = CMTime(seconds: toleranceAfter, preferredTimescale: 600)
        
        avPlayer.seek(to: targetTime, toleranceBefore: tolBefore, toleranceAfter: tolAfter) { finished in
            Task { @MainActor in
                completion?(finished)
            }
        }
    }
    
    public func tearDown() {
        if let token = timeObserverToken {
            avPlayer.removeTimeObserver(token)
            timeObserverToken = nil
        }
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
    }
}
