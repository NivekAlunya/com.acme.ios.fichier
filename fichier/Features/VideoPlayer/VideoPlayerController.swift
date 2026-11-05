//
//  VideoPlayerController.swift
//  fichier
//

import SwiftUI
import AVKit
import Observation
import OSLog

/// Master `@Observable` controller isolated to the `@MainActor` driving custom AVPlayer video playback.
///
/// ### Core Responsibilities
/// - **Asset Initialization & Streaming**: Plays local and cached files directly, or configures on-demand SMB
///   streaming using custom `smbstream://` URLs handled by `SMBResourceLoaderDelegate`.
/// - **Playback State Machine**: Tracks state transitions across `.idle`, `.loading`, `.buffering`, `.playing`,
///   `.paused`, and `.failed` with continuous `timeControlStatus` monitoring.
/// - **Progress Preservation**: Automatically restores saved playback timestamps from `VideoPlaybackStore`
///   (suppressed if video was previously finished or within 4.0s of ending) and debounces real-time progress saves.
/// - **Audio Session Management**: Activates `.playback` mode on `AVAudioSession` on background threads to ensure
///   uninterrupted playback through system mute switches.
/// - **Picture-in-Picture & Tracks**: Coordinates inline PiP via `CustomVideoPlayerCoordinator` and track selection
///   via `VideoTrackManager`.
/// - **Error Sanitization**: Redacts network IP addresses and SMB user credentials from user-facing error dialogs.
@Observable
@MainActor
public final class VideoPlayerController {
    /// Shared storage location manager handling network workers and credentials.
    public let manager: StorageLocationManager
    
    /// Playlist of video items available in the active playback queue.
    public let videos: [MediaItem]
    
    /// The currently selected video media item.
    public var currentItem: MediaItem
    
    /// The video media item currently mounted and playing in the AVPlayer instance.
    public private(set) var currentlyLoadedItem: MediaItem?
    
    /// Underlying AVFoundation player instance.
    public private(set) var player: AVPlayer?
    
    /// Architectural kind of the active playback engine.
    public private(set) var engineKind: VideoEngineKind = .native
    
    /// Abstract active playback engine conforming to `VideoPlayerEngineProtocol`.
    public private(set) var engine: (any VideoPlayerEngineProtocol)?
    
    /// Underlying native AVFoundation engine if active.
    public private(set) var nativeEngine: NativePlayerEngine?
    
    /// Underlying extended MobileVLCKit engine if active.
    public private(set) var extendedEngine: ExtendedPlayerEngine?
    
    /// Local loopback HTTP streaming server serving byte-range queries over SMB.
    private var smbStreamingServer: SMBStreamingServerActor?
    
    /// Current AVURLAsset reference configured for custom resource loading.
    private var currentAsset: AVURLAsset?
    
    /// Active resource loader delegate streaming chunks over SMB.
    private var loaderDelegate: SMBResourceLoaderDelegate?
    
    /// Current high-level playback state.
    public var playbackState: VideoPlaybackState = .idle
    
    /// User-presentable sanitized error description, or `nil` if healthy.
    public var errorMessage: String?
    
    /// Current playback progress in seconds.
    public var currentPlaybackSeconds: Double = 0
    
    /// Total duration of the loaded video in seconds.
    public var totalDurationSeconds: Double = 0
    
    /// Current player volume level normalized between `0.0` and `1.0`.
    public var volume: Double = 1.0
    
    /// Indicates whether audio output is currently muted.
    public var isMuted: Bool = false
    
    /// Controls visibility of floating top, center, and bottom HUD overlays.
    public var showControls: Bool = true
    
    /// Indicates whether Picture-in-Picture presentation is actively running.
    public var isPiPActive: Bool = false
    
    /// Coordinator managing Picture-in-Picture lifecycle and delegate callbacks.
    public let pipCoordinator = CustomVideoPlayerCoordinator()
    
    /// Manager handling audio tracks, subtitle streams, and playback speed.
    public let trackManager = VideoTrackManager()
    
    /// Coordinator managing timeline scrubbing, live frame seeking, and debounce timers.
    public let seekCoordinator = VideoSeekCoordinator()
    
    /// Indicates whether export to Camera Roll is actively in flight.
    public var isSaving: Bool = false
    
    /// Temporary toast message displayed after saving to Camera Roll.
    public var saveStatusMessage: String?
    
    /// Local file URL suitable for sharing via the system share sheet.
    public var shareableVideoURL: URL?
    
    /// Temporary toast banner notifying the user that playback resumed from a saved position.
    public var resumedToastMessage: String?
    
    /// Indicates whether playback started by restoring a previously saved timestamp.
    public var didRestorePlaybackPosition: Bool = false
    
    /// The timestamp in seconds from which playback was restored.
    public var restoredFromSeconds: Double?
    
    /// Timestamp when playback began for this video.
    public var playbackStartTime: Date = Date()
    
    private var hideControlsTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var resumeBannerTask: Task<Void, Never>?
    private var periodicTimeObserverToken: Any?
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - manager: Shared storage location manager.
    ///   - videos: Array of candidate media items (filtered for video types).
    ///   - initialItem: Initial video media item to load.
    public init(
        manager: StorageLocationManager,
        videos: [MediaItem],
        initialItem: MediaItem
    ) {
        self.manager = manager
        let vids = videos.filter { $0.isVideo }
        self.videos = vids.isEmpty ? [initialItem] : vids
        self.currentItem = initialItem
    }
    
    /// Indicates whether the current video reached its end timestamp and is in a terminal paused state.
    public var isAtEnd: Bool {
        totalDurationSeconds > 1.0 && currentPlaybackSeconds >= totalDurationSeconds - 0.5 && !playbackState.isPlaying
    }
    
    /// Zero-based index of the current video within the active playlist.
    public var currentIndex: Int {
        videos.firstIndex(where: { $0.id == currentItem.id }) ?? 0
    }
    
    /// Loads and begins playback of a specified media item.
    ///
    /// - Parameter item: Target video media item.
    public func loadItem(_ item: MediaItem) {
        setupPlayer(for: item)
    }
    
    /// Initializes player instances, audio session, and resource loaders for a video item.
    ///
    /// - Parameter item: The media item to mount and play.
    public func setupPlayer(for item: MediaItem) {
        playbackStartTime = Date()
        didRestorePlaybackPosition = false
        restoredFromSeconds = nil
        tearDownPlayer(deactivateAudioSession: false)
        currentlyLoadedItem = item
        showControls = true
        playbackState = .loading(item)
        errorMessage = nil
        
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
            } catch {
                AppLog.player.error("Failed to activate audio session: \(error.localizedDescription)")
            }
        }
        
        let ext = (item.name as NSString).pathExtension
        let isExtended = SupportedMediaTypes.isExtendedVideo(extension: ext)
        
        // 1. If local file or cached locally, play immediately from file
        if let localURL = item.localURL ?? (MediaCacheManager.shared.hasCachedVideo(for: item) ? MediaCacheManager.shared.localVideoURL(for: item) : nil) {
            self.shareableVideoURL = localURL
            if isExtended {
                setupExtendedEngine(with: localURL, for: item)
                return
            }
            
            self.engineKind = .native
            let avPlayer = AVPlayer(url: localURL)
            self.player = avPlayer
            let native = NativePlayerEngine(
                player: avPlayer,
                onTimeUpdate: { [weak self] time in
                    self?.currentPlaybackSeconds = time
                },
                onDurationUpdate: { [weak self] duration in
                    self?.totalDurationSeconds = duration
                },
                onStateUpdate: { [weak self] state in
                    self?.playbackState = state
                }
            )
            self.nativeEngine = native
            self.engine = native
            self.playbackState = .playing
            configurePlayer(avPlayer, for: item, loadTracksImmediately: true)
            avPlayer.play()
            self.scheduleControlsAutoHide()
            startContinuousPlaybackMonitoring(for: avPlayer)
            return
        }
        
        // 2. Apple Photos Library Video or Progressive On-Demand SMB Stream
        loadTask = Task { @MainActor in
            if item.phAssetIdentifier != nil {
                do {
                    let videoURL = try await manager.fetchVideoURL(for: item)
                    guard !Task.isCancelled else { return }
                    self.shareableVideoURL = videoURL
                    self.engineKind = .native
                    let avPlayer = AVPlayer(url: videoURL)
                    self.player = avPlayer
                    let native = NativePlayerEngine(
                        player: avPlayer,
                        onTimeUpdate: { [weak self] time in
                            self?.currentPlaybackSeconds = time
                        },
                        onDurationUpdate: { [weak self] duration in
                            self?.totalDurationSeconds = duration
                        },
                        onStateUpdate: { [weak self] state in
                            self?.playbackState = state
                        }
                    )
                    self.nativeEngine = native
                    self.engine = native
                    self.playbackState = .playing
                    configurePlayer(avPlayer, for: item, loadTracksImmediately: true)
                    avPlayer.play()
                    self.scheduleControlsAutoHide()
                    startContinuousPlaybackMonitoring(for: avPlayer)
                } catch {
                    guard !Task.isCancelled else { return }
                    let sanitized = self.sanitizeErrorDescription(error.localizedDescription)
                    let desc = String(localized: .Strings.videoPlayerErrorPlayback(sanitized))
                    self.errorMessage = desc
                    self.playbackState = .failed(desc)
                }
                return
            }
            
            let validItem = await manager.resolveValidItem(for: item)
            guard !Task.isCancelled else { return }
            
            if isExtended {
                self.engineKind = .extended
                self.player = nil
                self.playbackState = .buffering
                
                let server = SMBStreamingServerActor(worker: self.manager.clientActor, item: validItem)
                self.smbStreamingServer = server
                
                do {
                    let streamURL = try await server.start()
                    guard !Task.isCancelled else { return }
                    self.setupExtendedEngine(with: streamURL, for: validItem)
                } catch {
                    guard !Task.isCancelled else { return }
                    let sanitized = self.sanitizeErrorDescription(error.localizedDescription)
                    let desc = String(localized: .Strings.videoPlayerErrorPlayback(sanitized))
                    self.errorMessage = desc
                    self.playbackState = .failed(desc)
                }
                return
            }
            
            self.engineKind = .native
            guard validItem.size > 0, let (streamURL, uniqueID) = StorageLocationManager.makeStreamURL(for: validItem.name) else {
                let desc = String(localized: .Strings.videoPlayerErrorInvalidStreamUrl)
                self.errorMessage = desc
                self.playbackState = .failed(desc)
                return
            }
            
            let asset = AVURLAsset(url: streamURL)
            self.currentAsset = asset
            let delegate = SMBResourceLoaderDelegate(worker: self.manager.clientActor, item: validItem, chunkSize: 512 * 1024)
            self.loaderDelegate = delegate
            
            // swiftlint:disable:next no_legacy_dispatch_queue
            let queue = DispatchQueue(label: "com.acme.ios.photos.videoloader.\(uniqueID)", qos: .userInitiated)
            asset.resourceLoader.setDelegate(delegate, queue: queue)
            
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 2.0
            let avPlayer = AVPlayer(playerItem: playerItem)
            avPlayer.automaticallyWaitsToMinimizeStalling = true
            self.player = avPlayer
            let native = NativePlayerEngine(
                player: avPlayer,
                onTimeUpdate: { [weak self] time in
                    self?.currentPlaybackSeconds = time
                },
                onDurationUpdate: { [weak self] duration in
                    self?.totalDurationSeconds = duration
                },
                onStateUpdate: { [weak self] state in
                    self?.playbackState = state
                }
            )
            self.nativeEngine = native
            self.engine = native
            self.playbackState = .buffering
            configurePlayer(avPlayer, for: validItem, loadTracksImmediately: false)
            avPlayer.play()
            startContinuousPlaybackMonitoring(for: avPlayer)
        }
    }
    
    /// Configures and mounts the extended playback engine for open video containers and codecs.
    private func setupExtendedEngine(with url: URL, for item: MediaItem) {
        self.engineKind = .extended
        self.player = nil
        let extended = ExtendedPlayerEngine(
            url: url,
            onTimeUpdate: { [weak self] time in
                self?.currentPlaybackSeconds = time
            },
            onDurationUpdate: { [weak self] duration in
                self?.totalDurationSeconds = duration
            },
            onStateUpdate: { [weak self] state in
                self?.playbackState = state
            },
            onPlaybackEnded: { [weak self] in
                self?.handlePlaybackCompletion()
            }
        )
        self.extendedEngine = extended
        self.engine = extended
        self.playbackState = .buffering
        self.restorePlaybackPosition(for: item, knownDuration: self.totalDurationSeconds > 0 ? self.totalDurationSeconds : nil) { savedSeconds in
            extended.seek(to: savedSeconds, toleranceBefore: 0, toleranceAfter: 0, completion: nil)
        }
        extended.play()
        self.scheduleControlsAutoHide()
    }
    
    /// Restores saved playback position from persistent store if applicable.
    private func restorePlaybackPosition(for item: MediaItem, knownDuration: Double?, seekAction: (Double) -> Void) {
        if let savedSeconds = VideoPlaybackStore.shared.position(for: item) {
            let duration = knownDuration ?? 0
            if duration.isFinite && duration > 0 && (savedSeconds >= duration - 4.0 || savedSeconds / duration >= 0.90) {
                self.currentPlaybackSeconds = 0
                self.didRestorePlaybackPosition = false
                self.restoredFromSeconds = nil
            } else {
                seekAction(savedSeconds)
                self.currentPlaybackSeconds = savedSeconds
                self.didRestorePlaybackPosition = true
                self.restoredFromSeconds = savedSeconds
                showResumeBanner(at: savedSeconds)
            }
        } else {
            self.currentPlaybackSeconds = 0
            self.didRestorePlaybackPosition = false
            self.restoredFromSeconds = nil
        }
    }
    
    /// Configures volume, saved resume positions, periodic time observers, and track managers.
    private func configurePlayer(_ avPlayer: AVPlayer, for item: MediaItem, loadTracksImmediately: Bool) {
        self.volume = Double(avPlayer.volume)
        self.isMuted = avPlayer.isMuted
        
        // 1. Resume saved position if available
        restorePlaybackPosition(for: item, knownDuration: avPlayer.currentItem?.duration.seconds) { savedSeconds in
            let targetTime = CMTime(seconds: savedSeconds, preferredTimescale: 600)
            avPlayer.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        
        // 2. Set playback rate
        trackManager.setPlaybackRate(trackManager.playbackRate, for: avPlayer)
        
        // 3. Load media tracks immediately for local files
        if loadTracksImmediately, let currentItem = avPlayer.currentItem {
            Task { @MainActor in
                await trackManager.loadTracks(for: currentItem)
            }
        }
        
        // 4. Periodic time observer to remember playback progress & update timeline
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        self.periodicTimeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak avPlayer] time in
            MainActor.assumeIsolated {
                guard let self, let p = avPlayer, let current = p.currentItem else { return }
                let secs = time.seconds
                let dur = current.duration.seconds
                
                if !self.seekCoordinator.isScrubbing {
                    if secs.isFinite && !secs.isNaN {
                        self.currentPlaybackSeconds = secs
                    }
                }
                if dur.isFinite && !dur.isNaN && dur > 0 {
                    self.totalDurationSeconds = dur
                }
                
                if self.didRestorePlaybackPosition, let restored = self.restoredFromSeconds {
                    if abs(secs - restored) > 2.5 {
                        self.didRestorePlaybackPosition = false
                        self.restoredFromSeconds = nil
                    }
                }
                
                let isCurrentlyPlaying = (p.timeControlStatus != .paused)
                let wasPlaying = self.playbackState.isPlaying
                if !self.seekCoordinator.isFinishingSeek {
                    if isCurrentlyPlaying && self.playbackState != .playing {
                        self.playbackState = .playing
                    } else if !isCurrentlyPlaying && self.playbackState == .playing {
                        self.playbackState = .paused
                    }
                }
                
                if self.playbackState.isBuffering && (p.timeControlStatus == .playing || p.rate > 0 || current.isPlaybackLikelyToKeepUp) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.playbackState = isCurrentlyPlaying ? .playing : .paused
                    }
                    self.scheduleControlsAutoHide()
                } else if !wasPlaying && isCurrentlyPlaying {
                    self.scheduleControlsAutoHide()
                }
                
                if !self.seekCoordinator.isScrubbing && secs.isFinite && !secs.isNaN && dur.isFinite && !dur.isNaN && secs >= 2.0 {
                    VideoPlaybackStore.shared.savePosition(secs, duration: dur, for: item)
                }
            }
        }
    }
    
    /// Continuous background monitoring task checking AVPlayer health and buffering states every 120ms.
    private func startContinuousPlaybackMonitoring(for avPlayer: AVPlayer) {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor [weak self, weak avPlayer] in
            var tracksLoaded = false
            var waitingStartTime: Date?
            
            while !Task.isCancelled {
                guard let self, let p = avPlayer else { break }
                let playerItem = p.currentItem
                
                // 1. Terminal error check
                let playbackError = p.error ?? playerItem?.error
                if playbackError != nil || p.status == .failed || playerItem?.status == .failed {
                    let desc = playbackError?.localizedDescription ?? "Playback error"
                    let sanitized = self.sanitizeErrorDescription(desc)
                    let localizedDesc = String(localized: .Strings.videoPlayerErrorPlayback(sanitized))
                    self.errorMessage = localizedDesc
                    self.playbackState = .failed(localizedDesc)
                    break
                }
                
                // 2. Load audio/subtitle tracks once playerItem is ready
                if !tracksLoaded, let item = playerItem, item.status == .readyToPlay {
                    tracksLoaded = true
                    Task { @MainActor in
                        await self.trackManager.loadTracks(for: item)
                    }
                }
                
                // 3. Continuous timeControlStatus monitoring
                switch p.timeControlStatus {
                case .playing:
                    waitingStartTime = nil
                    if self.playbackState.isBuffering {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.playbackState = .playing
                        }
                    }
                    if !self.playbackState.isPlaying {
                        self.playbackState = .playing
                        self.scheduleControlsAutoHide()
                    }
                    
                case .paused:
                    waitingStartTime = nil
                    if self.playbackState.isBuffering {
                        if playerItem?.status == .readyToPlay {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.playbackState = .paused
                            }
                        }
                    }
                    if self.playbackState.isPlaying && !self.seekCoordinator.isScrubbing && !self.seekCoordinator.isFinishingSeek {
                        self.playbackState = .paused
                    }
                    
                case .waitingToPlayAtSpecifiedRate:
                    if waitingStartTime == nil {
                        waitingStartTime = Date()
                    } else if let start = waitingStartTime, Date().timeIntervalSince(start) > 0.85 {
                        if !self.playbackState.isBuffering && !self.seekCoordinator.isScrubbing {
                            self.cancelAutoHideTimer()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.playbackState = .buffering
                            }
                        }
                    }
                @unknown default:
                    break
                }
                
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }
    
    /// Sets normalized volume across active player engine and AVPlayer instance.
    public func setVolume(_ newVolume: Double) {
        self.volume = max(0.0, min(1.0, newVolume))
        self.engine?.volume = self.volume
        self.player?.volume = Float(self.volume)
    }
    
    /// Sets muted state across active player engine and AVPlayer instance.
    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        self.engine?.isMuted = muted
        self.player?.isMuted = muted
    }
    
    /// Configures playback rate multiplier across active manager and engines.
    public func setPlaybackRate(_ rate: VideoPlaybackRate) {
        trackManager.setPlaybackRate(rate, for: self.engine)
        if let player = self.player {
            trackManager.setPlaybackRate(rate, for: player)
        }
    }
    
    /// Toggles between playing and paused states, wrapping to beginning if reaching the end.
    public func togglePlayPause() {
        if isAtEnd {
            seekTo(0, resumePlaying: true)
            currentPlaybackSeconds = 0
            return
        }
        
        let currentlyPlaying = engine?.isPlaying ?? (player?.timeControlStatus != .paused)
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
        hideControlsTask?.cancel()
    }
    
    /// Performs an exact seek to a specific timestamp in seconds.
    public func seekTo(_ targetSeconds: Double, resumePlaying: Bool = false) {
        finishSeeking(at: targetSeconds, resumePlaying: resumePlaying)
    }
    
    /// Jumps forward or backward relative to the current playback position.
    ///
    /// - Parameter deltaSeconds: Offset in seconds (e.g. +10 or -10).
    public func seekRelative(_ deltaSeconds: Double) {
        let current = currentPlaybackSeconds
        let dur = totalDurationSeconds > 0 ? totalDurationSeconds : (player?.currentItem?.duration.seconds ?? 0)
        let maxLimit = dur > 0 ? dur : max(current + deltaSeconds, 0)
        let newTarget = min(max(0, current + deltaSeconds), maxLimit)
        let resume = (engine?.isPlaying ?? (player?.timeControlStatus != .paused)) || playbackState.isPlaying
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
        finishSeeking(at: targetSeconds, resumePlaying: seekCoordinator.wasPlayingBeforeScrub)
    }
    
    /// Callback from timeline scrubber as the user actively drags their finger.
    public func onTimelineScrubbing(targetSeconds: Double) {
        currentPlaybackSeconds = targetSeconds
        if let engine {
            seekCoordinator.requestLiveFrameSeek(to: targetSeconds, engine: engine)
        } else {
            seekCoordinator.requestLiveFrameSeek(to: targetSeconds, player: player)
        }
    }
    
    /// Callback tracking changes in timeline scrubbing active state.
    public func onTimelineScrubStateChanged(isScrubbing: Bool) {
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
        isSaving = true
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            do {
                let localURL = try await manager.fetchVideoURL(for: currentItem)
                guard !Task.isCancelled else { return }
                self.shareableVideoURL = localURL
                try await PhotoLibrarySaver.saveVideoToPhotos(at: localURL)
                guard !Task.isCancelled else { return }
                withAnimation {
                    saveStatusMessage = String(localized: .Strings.videoPlayerSavedToPhotos)
                }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation {
                    saveStatusMessage = String(localized: .Strings.commonErrorFailedToSave(error.localizedDescription))
                }
            }
            isSaving = false
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation {
                saveStatusMessage = nil
            }
        }
    }
    
    /// Restarts the video from `0:00` and purges any saved resume progress from persistent store.
    public func restartVideo() {
        guard engine != nil || player != nil else { return }
        let targetItem = currentlyLoadedItem ?? currentItem
        didRestorePlaybackPosition = false
        restoredFromSeconds = nil
        resumeBannerTask?.cancel()
        seekTo(0, resumePlaying: playbackState.isPlaying)
        currentPlaybackSeconds = 0
        VideoPlaybackStore.shared.clearPosition(for: targetItem)
        withAnimation {
            resumedToastMessage = nil
        }
    }
    
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
        guard totalSeconds.isFinite && !totalSeconds.isNaN && totalSeconds >= 0 else { return "0:00" }
        let secs = Int(totalSeconds)
        let hours = secs / 3600
        let minutes = (secs % 3600) / 60
        let seconds = secs % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Schedules automatic fading of HUD overlay controls after a period of user inactivity.
    ///
    /// - Parameter delay: Delay in seconds (defaults to 3.5s).
    public func scheduleControlsAutoHide(delay: Double = 3.5) {
        guard showControls && playbackState.isPlaying && !playbackState.isBuffering && !seekCoordinator.isScrubbing else {
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
        if showControls && playbackState.isPlaying {
            scheduleControlsAutoHide()
        }
    }
    
    /// Toggles the visibility of overlay HUD controls.
    public func toggleControls() {
        guard !seekCoordinator.isScrubbing else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            showControls.toggle()
        }
        if showControls {
            scheduleControlsAutoHide()
        } else {
            hideControlsTask?.cancel()
        }
    }
    
    /// Action handler for two-finger tap gestures, toggling play and pause with haptic feedback.
    public func handleTwoFingerTap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        togglePlayPause()
    }
    
    /// Tears down the active player instance, flushing saved progress and cancelling in-flight tasks.
    ///
    /// - Parameter deactivateAudioSession: Whether to release the system audio session.
    public func tearDownPlayer(deactivateAudioSession: Bool = false) {
        if let currentEngine = engine, let loadedItem = currentlyLoadedItem {
            let secs = currentEngine.currentTimeSeconds
            let dur = currentEngine.durationSeconds
            let isNearEnd = dur > 0 && secs >= dur * 0.90
            if secs.isFinite && !secs.isNaN && dur.isFinite && !dur.isNaN && secs >= 2.0 && !isNearEnd {
                VideoPlaybackStore.shared.savePosition(secs, duration: dur, for: loadedItem)
            }
        } else if let p = player, let current = p.currentItem, let loadedItem = currentlyLoadedItem {
            let secs = p.currentTime().seconds
            let dur = current.duration.seconds
            let isNearEnd = dur > 0 && secs >= dur * 0.90
            if secs.isFinite && !secs.isNaN && dur.isFinite && !dur.isNaN && secs >= 2.0 && !isNearEnd {
                VideoPlaybackStore.shared.savePosition(secs, duration: dur, for: loadedItem)
            }
        }
        currentlyLoadedItem = nil
        shareableVideoURL = nil
        VideoPlaybackStore.shared.flush()
        if let token = periodicTimeObserverToken {
            player?.removeTimeObserver(token)
            periodicTimeObserverToken = nil
        }
        resumeBannerTask?.cancel()
        resumeBannerTask = nil
        resumedToastMessage = nil
        trackManager.reset()
        
        hideControlsTask?.cancel()
        hideControlsTask = nil
        seekCoordinator.reset()
        loadTask?.cancel()
        loadTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        saveTask?.cancel()
        saveTask = nil
        loaderDelegate?.cancelAll()
        loaderDelegate = nil
        currentAsset?.resourceLoader.setDelegate(nil, queue: nil)
        currentAsset = nil
        
        Task { [server = smbStreamingServer] in
            await server?.stop()
        }
        smbStreamingServer = nil
        extendedEngine?.tearDown()
        extendedEngine = nil
        nativeEngine?.tearDown()
        nativeEngine = nil
        engine = nil
        
        player?.pause()
        player = nil
        playbackState = .idle
        errorMessage = nil
        
        if deactivateAudioSession {
            Task.detached(priority: .utility) {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
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
        guard let item = notification.object as? AVPlayerItem,
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
            let sanitized = sanitizeErrorDescription(error.localizedDescription)
            let desc = String(localized: .Strings.videoPlayerErrorPlayback(sanitized))
            self.errorMessage = desc
            self.playbackState = .failed(desc)
        }
    }
    
    /// Saves current playback progress when the application enters the background scene phase.
    public func handleScenePhaseBackground() {
        if let p = player, let loadedItem = currentlyLoadedItem {
            let secs = p.currentTime().seconds
            let dur = p.currentItem?.duration.seconds ?? 0
            VideoPlaybackStore.shared.savePosition(secs, duration: dur, for: loadedItem)
        }
        VideoPlaybackStore.shared.flush()
    }
    
    // MARK: - Error Sanitization
    
    /// Strips sensitive host IP addresses and SMB connection credentials from error message strings.
    private func sanitizeErrorDescription(_ rawDescription: String) -> String {
        // Redact IP addresses (e.g. 192.168.1.100)
        var sanitized = rawDescription.replacingOccurrences(
            of: #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#,
            with: "<host>",
            options: .regularExpression
        )
        // Redact SMB URLs/credentials (e.g. smb://user:pass@host/share)
        sanitized = sanitized.replacingOccurrences(
            of: #"smb://[^\s/]+"#,
            with: "smb://<server>",
            options: .regularExpression
        )
        return sanitized
    }
}
