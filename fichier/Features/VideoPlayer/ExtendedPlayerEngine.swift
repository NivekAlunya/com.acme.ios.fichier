//
//  ExtendedPlayerEngine.swift
//  fichier
//

import Foundation
import UIKit
#if canImport(VLCKit)
import VLCKit
#endif

/// Extended playback engine leveraging VLCKit (VideoLAN LibVLC).
///
/// Conforms to `VideoPlayerEngineProtocol` to decode open containers (MKV, AVI, WebM, FLV, WMV, TS, OGV, RM)
/// and non-native audio/subtitle formats (Vorbis, DTS, TrueHD, SSA/ASS) within the unified Fichier player pipeline.
@MainActor
public final class ExtendedPlayerEngine: NSObject, VideoPlayerEngineProtocol {
    public let engineKind: VideoEngineKind = .extended
    
    #if canImport(VLCKit)
    /// Active VLCKit media player instance.
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
    private var isTornDown: Bool = false
    private var didStartPlayback: Bool = false
    private var didEmitPlaybackEnded: Bool = false
    
    private var onTimeUpdate: (@MainActor @Sendable (Double) -> Void)?
    private var onDurationUpdate: (@MainActor @Sendable (Double) -> Void)?
    private var onStateUpdate: (@MainActor @Sendable (VideoPlaybackState) -> Void)?
    private var onPlaybackEnded: (@MainActor @Sendable () -> Void)?
    public var onTracksChanged: (@MainActor @Sendable () -> Void)?
    
    private var lastKnownAudioTrackCount: Int = 0
    private var lastKnownSubtitleTrackCount: Int = 0
    
    @MainActor
    private func emitState(_ state: VideoPlaybackState) {
        if lastEmittedState != state {
            lastEmittedState = state
            onStateUpdate?(state)
        }
    }
    
    public var isPlaying: Bool {
        #if canImport(VLCKit)
        return vlcPlayer.isPlaying
        #else
        return isPlayingInternal
        #endif
    }
    
    public var currentTimeSeconds: Double {
        #if canImport(VLCKit)
        let ms = Double(vlcPlayer.time.intValue)
        let sec = ms / 1000.0
        return (sec.isFinite && !sec.isNaN && sec >= 0) ? sec : currentTimeInternal
        #else
        return currentTimeInternal
        #endif
    }
    
    public var durationSeconds: Double {
        #if canImport(VLCKit)
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
            #if canImport(VLCKit)
            vlcPlayer.audio?.volume = Int32(volumeInternal * 100.0)
            #endif
        }
    }
    
    public var isMuted: Bool {
        get { isMutedInternal }
        set {
            isMutedInternal = newValue
            #if canImport(VLCKit)
            vlcPlayer.audio?.isMuted = newValue
            #endif
        }
    }
    
    public var playbackRate: VideoPlaybackRate = .normal {
        didSet {
            #if canImport(VLCKit)
            vlcPlayer.rate = playbackRate.rawValue
            #endif
        }
    }
    
    /// Discovered audio tracks in the active VLC media item.
    public var audioTrackOptions: [VideoTrackOption] {
        #if canImport(VLCKit)
        let tracks = vlcPlayer.audioTracks
        var audioOptions: [VideoTrackOption] = []
        for (index, track) in tracks.enumerated() {
            let rawName = track.trackName.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawDesc = (track.trackDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName: String
            if !rawName.isEmpty {
                displayName = rawName
            } else if !rawDesc.isEmpty {
                displayName = rawDesc
            } else {
                displayName = String(localized: .Strings.videoPlayerTrackFallback(index + 1))
            }
            let trackIndex = Int32(index)
            let trackID = "vlc_audio_\(index)_\(displayName)"
            audioOptions.append(
                VideoTrackOption(id: trackID, displayName: displayName, mediaOption: nil, vlcTrackIndex: trackIndex)
            )
        }
        return audioOptions
        #else
        return []
        #endif
    }
    
    private var preferredAudioTrackIndex: Int32?
    private var preferredSubtitleTrackIndex: Int32?
    
    /// Active audio track index on LibVLC.
    public var currentAudioTrackIndex: Int32 {
        get {
            #if canImport(VLCKit)
            if let preferred = preferredAudioTrackIndex {
                return preferred
            }
            if let selectedIndex = vlcPlayer.audioTracks.firstIndex(where: \.isSelected) {
                return Int32(selectedIndex)
            }
            return -1
            #else
            return preferredAudioTrackIndex ?? -1
            #endif
        }
        set {
            preferredAudioTrackIndex = newValue
            #if canImport(VLCKit)
            if newValue >= 0 {
                vlcPlayer.selectTrack(at: Int(newValue), type: .audio)
            } else {
                vlcPlayer.deselectAllAudioTracks()
            }
            #endif
        }
    }
    
    /// Discovered subtitle options in the active VLC media item, prefixed with synthetic 'Off' if tracks exist.
    public var subtitleTrackOptions: [VideoTrackOption] {
        #if canImport(VLCKit)
        let tracks = vlcPlayer.textTracks
        guard !tracks.isEmpty else {
            return []
        }
        
        var subOptions: [VideoTrackOption] = []
        for (index, track) in tracks.enumerated() {
            let rawName = track.trackName.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawDesc = (track.trackDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName: String
            if !rawName.isEmpty {
                displayName = rawName
            } else if !rawDesc.isEmpty {
                displayName = rawDesc
            } else {
                displayName = String(localized: .Strings.videoPlayerSubtitleFallback(index + 1))
            }
            let trackIndex = Int32(index)
            let trackID = "vlc_sub_\(index)_\(displayName)"
            subOptions.append(
                VideoTrackOption(id: trackID, displayName: displayName, mediaOption: nil, vlcTrackIndex: trackIndex)
            )
        }
        
        let offOption = VideoTrackOption(
            id: "sub_off",
            displayName: String(localized: .Strings.videoPlayerSubtitlesOff),
            mediaOption: nil,
            vlcTrackIndex: -1
        )
        return [offOption] + subOptions
        #else
        return []
        #endif
    }
    
    /// Active subtitle track index on LibVLC (-1 indicates disabled).
    public var currentSubtitleTrackIndex: Int32 {
        get {
            #if canImport(VLCKit)
            if let preferred = preferredSubtitleTrackIndex {
                return preferred
            }
            if let selectedIndex = vlcPlayer.textTracks.firstIndex(where: \.isSelected) {
                return Int32(selectedIndex)
            }
            return -1
            #else
            return preferredSubtitleTrackIndex ?? -1
            #endif
        }
        set {
            preferredSubtitleTrackIndex = newValue
            #if canImport(VLCKit)
            if newValue >= 0 {
                vlcPlayer.selectTrack(at: Int(newValue), type: .text)
            } else {
                vlcPlayer.deselectAllTextTracks()
            }
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
    ///   - onTracksChanged: Callback triggered when available audio or subtitle tracks change.
    public init(
        url: URL,
        onTimeUpdate: (@MainActor @Sendable (Double) -> Void)? = nil,
        onDurationUpdate: (@MainActor @Sendable (Double) -> Void)? = nil,
        onStateUpdate: (@MainActor @Sendable (VideoPlaybackState) -> Void)? = nil,
        onPlaybackEnded: (@MainActor @Sendable () -> Void)? = nil,
        onTracksChanged: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.onTimeUpdate = onTimeUpdate
        self.onDurationUpdate = onDurationUpdate
        self.onStateUpdate = onStateUpdate
        self.onPlaybackEnded = onPlaybackEnded
        self.onTracksChanged = onTracksChanged
        
        #if canImport(VLCKit)
        let player = VLCMediaPlayer()
        player.media = VLCMedia(url: url)
        player.drawable = renderView
        self.vlcPlayer = player
        #endif
        
        super.init()
        
        #if canImport(VLCKit)
        vlcPlayer.delegate = self
        #endif
    }
    
    public func play() {
        #if canImport(VLCKit)
        guard vlcPlayer.media != nil else {
            isPlayingInternal = false
            emitState(.failed("Unable to load media with VLCKit"))
            return
        }
        isPlayingInternal = true
        vlcPlayer.play()
        #else
        isPlayingInternal = true
        #endif
    }
    
    public func pause() {
        isPlayingInternal = false
        #if canImport(VLCKit)
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
        let safeSeconds = (seconds.isFinite && !seconds.isNaN) ? max(0, seconds) : 0
        currentTimeInternal = safeSeconds
        #if canImport(VLCKit)
        let targetMs = Int32(clamping: Int64(safeSeconds * 1000.0))
        vlcPlayer.time = VLCTime(int: targetMs)
        completion?(true)
        #else
        completion?(true)
        #endif
    }
    
    public func tearDown() {
        isTornDown = true
        isPlayingInternal = false
        didStartPlayback = false
        lastEmittedState = nil
        onTracksChanged = nil
        #if canImport(VLCKit)
        vlcPlayer.delegate = nil
        vlcPlayer.stop()
        vlcPlayer.drawable = nil
        #endif
    }
}

#if canImport(VLCKit)
extension ExtendedPlayerEngine: VLCMediaPlayerDelegate {
    public nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            guard let self, !self.isTornDown else { return }
            let current = self.currentTimeSeconds
            if self.vlcPlayer.isPlaying {
                self.didStartPlayback = true
                self.isPlayingInternal = true
                self.emitState(.playing)
            }
            self.onTimeUpdate?(current)
            let dur = self.durationSeconds
            if dur > 0 {
                self.durationInternal = dur
                self.onDurationUpdate?(dur)
            }
            let audioCount = self.vlcPlayer.audioTracks.count
            let subCount = self.vlcPlayer.textTracks.count
            if audioCount != self.lastKnownAudioTrackCount || subCount != self.lastKnownSubtitleTrackCount {
                self.lastKnownAudioTrackCount = audioCount
                self.lastKnownSubtitleTrackCount = subCount
                self.onTracksChanged?()
            }
        }
    }
    
    public nonisolated func mediaPlayerLengthChanged(_ length: Int64) {
        Task { @MainActor [weak self] in
            guard let self, !self.isTornDown else { return }
            let dur = Double(length) / 1000.0
            if dur.isFinite && !dur.isNaN && dur > 0 {
                self.durationInternal = dur
                self.onDurationUpdate?(dur)
            }
        }
    }
    
    public nonisolated func mediaPlayerBufferingChanged(_ progress: Float) {
        Task { @MainActor [weak self] in
            guard let self, !self.isTornDown else { return }
            if progress < 1.0 {
                if self.lastEmittedState != .paused && !self.vlcPlayer.isPlaying {
                    self.isPlayingInternal = false
                    self.emitState(.buffering)
                }
            } else if self.vlcPlayer.isPlaying {
                self.didStartPlayback = true
                self.isPlayingInternal = true
                self.emitState(.playing)
            }
        }
    }
    
    public nonisolated func mediaPlayerTrackAdded(_ trackId: String, with type: VLCMedia.TrackType) {
        Task { @MainActor [weak self] in
            guard let self, !self.isTornDown else { return }
            self.lastKnownAudioTrackCount = self.vlcPlayer.audioTracks.count
            self.lastKnownSubtitleTrackCount = self.vlcPlayer.textTracks.count
            self.onTracksChanged?()
        }
    }
    
    public nonisolated func mediaPlayerTrackRemoved(_ trackId: String, with type: VLCMedia.TrackType) {
        Task { @MainActor [weak self] in
            guard let self, !self.isTornDown else { return }
            self.lastKnownAudioTrackCount = self.vlcPlayer.audioTracks.count
            self.lastKnownSubtitleTrackCount = self.vlcPlayer.textTracks.count
            self.onTracksChanged?()
        }
    }
    
    public nonisolated func mediaPlayerTrackUpdated(_ trackId: String, with type: VLCMedia.TrackType) {
        Task { @MainActor [weak self] in
            guard let self, !self.isTornDown else { return }
            self.onTracksChanged?()
        }
    }
    
    public nonisolated func mediaPlayerTrackSelected(
        _ trackType: VLCMedia.TrackType,
        selectedId: String,
        unselectedId: String
    ) {
        Task { @MainActor [weak self] in
            guard let self, !self.isTornDown else { return }
            self.onTracksChanged?()
        }
    }
    
    public nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        Task { @MainActor [weak self] in
            guard let self, !self.isTornDown else { return }
            switch newState {
            case .playing:
                self.didStartPlayback = true
                self.didEmitPlaybackEnded = false
                self.isPlayingInternal = true
                self.emitState(.playing)
            case .paused:
                self.isPlayingInternal = false
                self.emitState(.paused)
            case .opening:
                if self.vlcPlayer.isPlaying {
                    self.didStartPlayback = true
                    self.isPlayingInternal = true
                    self.emitState(.playing)
                } else {
                    self.isPlayingInternal = false
                    self.emitState(.buffering)
                }
            case .stopped:
                self.isPlayingInternal = false
                if case .failed = self.lastEmittedState {
                    return
                }
                if self.didStartPlayback && !self.didEmitPlaybackEnded {
                    self.didEmitPlaybackEnded = true
                    self.didStartPlayback = false
                    self.emitState(.paused)
                    self.onPlaybackEnded?()
                } else {
                    self.emitState(.paused)
                }
            case .error:
                self.isPlayingInternal = false
                self.didStartPlayback = false
                self.emitState(.failed("VLC playback error"))
            case .stopping, .nothingSpecial:
                break
            @unknown default:
                if self.vlcPlayer.isPlaying {
                    self.didStartPlayback = true
                    self.isPlayingInternal = true
                    self.emitState(.playing)
                }
            }
        }
    }
}
#endif
