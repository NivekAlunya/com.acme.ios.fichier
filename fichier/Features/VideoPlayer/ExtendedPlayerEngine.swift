//
//  ExtendedPlayerEngine.swift
//  fichier
//

import Foundation
import UIKit
#if canImport(MobileVLCKit)
import MobileVLCKit
#endif

/// Extended playback engine leveraging MobileVLCKit (VideoLAN LibVLC).
///
/// Conforms to `VideoPlayerEngineProtocol` to decode open containers (MKV, AVI, WebM, FLV, WMV, TS, OGV, RM)
/// and non-native audio/subtitle formats (Vorbis, DTS, TrueHD, SSA/ASS) within the unified Fichier player pipeline.
@MainActor
public final class ExtendedPlayerEngine: NSObject, VideoPlayerEngineProtocol {
    public let engineKind: VideoEngineKind = .extended
    
    #if canImport(MobileVLCKit)
    /// Active MobileVLCKit media player instance.
    public let vlcPlayer: VLCMediaPlayer
    #endif
    
    /// UIView container where LibVLC renders video frames.
    public let renderView: UIView = {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        return view
    }()
    
    private var isPlayingInternal: Bool = false
    private var currentTimeInternal: Double = 0
    private var durationInternal: Double = 0
    private var volumeInternal: Double = 1.0
    private var isMutedInternal: Bool = false
    private var lastEmittedState: VideoPlaybackState?
    
    private var onTimeUpdate: (@MainActor @Sendable (Double) -> Void)?
    private var onDurationUpdate: (@MainActor @Sendable (Double) -> Void)?
    private var onStateUpdate: (@MainActor @Sendable (VideoPlaybackState) -> Void)?
    private var onPlaybackEnded: (@MainActor @Sendable () -> Void)?
    
    @MainActor
    private func emitState(_ state: VideoPlaybackState) {
        if lastEmittedState != state {
            lastEmittedState = state
            onStateUpdate?(state)
        }
    }
    
    public var isPlaying: Bool {
        #if canImport(MobileVLCKit)
        return vlcPlayer.isPlaying
        #else
        return isPlayingInternal
        #endif
    }
    
    public var currentTimeSeconds: Double {
        #if canImport(MobileVLCKit)
        let ms = Double(vlcPlayer.time.intValue)
        let sec = ms / 1000.0
        return (sec.isFinite && !sec.isNaN && sec >= 0) ? sec : currentTimeInternal
        #else
        return currentTimeInternal
        #endif
    }
    
    public var durationSeconds: Double {
        #if canImport(MobileVLCKit)
        if let media = vlcPlayer.media {
            let ms = Double(media.length.intValue)
            let sec = ms / 1000.0
            return (sec.isFinite && !sec.isNaN && sec > 0) ? sec : durationInternal
        }
        return durationInternal
        #else
        return durationInternal
        #endif
    }
    
    public var volume: Double {
        get { volumeInternal }
        set {
            volumeInternal = max(0.0, min(1.0, newValue))
            #if canImport(MobileVLCKit)
            vlcPlayer.audio?.volume = Int32(volumeInternal * 100.0)
            #endif
        }
    }
    
    public var isMuted: Bool {
        get { isMutedInternal }
        set {
            isMutedInternal = newValue
            #if canImport(MobileVLCKit)
            vlcPlayer.audio?.isMuted = newValue
            #endif
        }
    }
    
    public var playbackRate: VideoPlaybackRate = .normal {
        didSet {
            #if canImport(MobileVLCKit)
            vlcPlayer.rate = playbackRate.rawValue
            #endif
        }
    }
    
    /// Designated initializer mounting the specified local or loopback HTTP stream URL.
    ///
    /// - Parameters:
    ///   - url: Target media stream URL.
    ///   - onTimeUpdate: Periodic time change callback.
    ///   - onDurationUpdate: Duration resolution callback.
    ///   - onStateUpdate: State machine transition callback.
    ///   - onPlaybackEnded: Completion callback when playback reaches the end.
    public init(
        url: URL,
        onTimeUpdate: (@MainActor @Sendable (Double) -> Void)? = nil,
        onDurationUpdate: (@MainActor @Sendable (Double) -> Void)? = nil,
        onStateUpdate: (@MainActor @Sendable (VideoPlaybackState) -> Void)? = nil,
        onPlaybackEnded: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.onTimeUpdate = onTimeUpdate
        self.onDurationUpdate = onDurationUpdate
        self.onStateUpdate = onStateUpdate
        self.onPlaybackEnded = onPlaybackEnded
        
        #if canImport(MobileVLCKit)
        let player = VLCMediaPlayer()
        let media = VLCMedia(url: url)
        player.media = media
        player.drawable = renderView
        self.vlcPlayer = player
        #endif
        
        super.init()
        
        #if canImport(MobileVLCKit)
        player.delegate = self
        #endif
    }
    
    public func play() {
        isPlayingInternal = true
        #if canImport(MobileVLCKit)
        vlcPlayer.play()
        #endif
    }
    
    public func pause() {
        isPlayingInternal = false
        #if canImport(MobileVLCKit)
        vlcPlayer.pause()
        #endif
        emitState(.paused)
    }
    
    public func seek(
        to seconds: Double,
        toleranceBefore: Double,
        toleranceAfter: Double,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        currentTimeInternal = seconds
        #if canImport(MobileVLCKit)
        let targetMs = Int32(max(0, seconds * 1000.0))
        vlcPlayer.time = VLCTime(int: targetMs)
        completion?(true)
        #else
        completion?(true)
        #endif
    }
    
    public func tearDown() {
        isPlayingInternal = false
        lastEmittedState = nil
        #if canImport(MobileVLCKit)
        vlcPlayer.stop()
        vlcPlayer.drawable = nil
        #endif
    }
}

#if canImport(MobileVLCKit)
extension ExtendedPlayerEngine: VLCMediaPlayerDelegate {
    public nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let current = self.currentTimeSeconds
            if self.vlcPlayer.isPlaying || current > 0 {
                self.isPlayingInternal = true
                self.emitState(.playing)
            }
            self.onTimeUpdate?(current)
            let dur = self.durationSeconds
            if dur > 0 {
                self.onDurationUpdate?(dur)
            }
        }
    }
    
    public nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.vlcPlayer.isPlaying {
                self.isPlayingInternal = true
                self.emitState(.playing)
                return
            }
            
            switch self.vlcPlayer.state {
            case .playing:
                self.isPlayingInternal = true
                self.emitState(.playing)
            case .paused:
                self.isPlayingInternal = false
                self.emitState(.paused)
            case .buffering, .opening:
                if self.vlcPlayer.isPlaying {
                    self.isPlayingInternal = true
                    self.emitState(.playing)
                } else {
                    self.isPlayingInternal = false
                    self.emitState(.buffering)
                }
            case .ended:
                self.isPlayingInternal = false
                self.emitState(.paused)
                self.onPlaybackEnded?()
            case .error:
                self.isPlayingInternal = false
                self.emitState(.failed("VLC playback error"))
            default:
                if self.vlcPlayer.isPlaying {
                    self.isPlayingInternal = true
                    self.emitState(.playing)
                }
            }
        }
    }
}
#endif
