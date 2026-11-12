//
//  VideoPlayerController.swift
//  fichier
//

import SwiftUI
import AVKit
import Observation
import Wappn
import FichierKit

/// Master `@Observable` controller isolated to the `@MainActor` driving custom native (`AVPlayerEngine`)
/// and extended (`TVVLCPlayerEngine`) video playback.
///
/// ### Core Responsibilities
/// - **Asset Initialization & Streaming**: Plays local and cached files directly, or configures on-demand SMB
///   streaming using custom `smbstream://` URLs handled by `FichierKit.SMBAVAssetResourceLoaderDelegate` or
///   direct authenticated `smb://` URLs via `TVVLCPlayerEngine` and `VLCPlaybackOptions`.
/// - **Playback State Machine**: Tracks state transitions across `.idle`, `.loading`, `.buffering`, `.playing`,
///   `.paused`, and `.failed` through `FichierKit` engine callbacks.
/// - **Progress Preservation**: Automatically restores saved playback timestamps from `VideoPlaybackStore`
///   (suppressed if video was previously finished or within 4.0s of ending) and debounces real-time progress saves.
/// - **Audio Session Management**: Activates `.playback` mode on `AVAudioSession` on background threads to ensure
///   uninterrupted playback through system mute switches.
/// - **Picture-in-Picture & Tracks**: Coordinates inline PiP via `CustomVideoPlayerCoordinator` and track selection
///   via `VideoTrackManager` (preserving `AVPlayerItemLegibleOutput` subtitle rendering).
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
    
    /// The video media item currently mounted and playing in the active playback engine.
    public private(set) var currentlyLoadedItem: MediaItem?
    
    /// Underlying AVFoundation player instance.
    public private(set) var player: AVPlayer?
    
    /// Architectural kind of the active playback engine.
    public private(set) var engineKind: PlayerEngineKind = .native
    
    /// Abstract active playback engine conforming to `FichierKit.PlayerEngine`.
    public private(set) var engine: (any PlayerEngine)?
    
    /// Underlying native AVFoundation engine if active.
    public private(set) var nativeEngine: AVPlayerEngine?
    
    /// Underlying extended VLCKit engine if active.
    public private(set) var extendedEngine: TVVLCPlayerEngine?
    
    /// Current AVURLAsset reference configured for custom resource loading.
    private var currentAsset: AVURLAsset?
    
    /// Active resource loader delegate streaming chunks over SMB.
    private var loaderDelegate: SMBAVAssetResourceLoaderDelegate?
    
    /// Current high-level playback state.
    public var playbackState: PlayerPlaybackState = .idle
    
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
    
    /// Available chapter markers parsed from the active media item.
    public private(set) var availableChapters: [PlayerChapter] = []
    
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
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var resumeBannerTask: Task<Void, Never>?
    
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
    
    /// Indicates whether the active playback engine or AVPlayer instance is actively rendering/advancing frames.
    public var isEnginePlaying: Bool {
        engine?.isPlaying == true || player?.timeControlStatus == .playing
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
    
    /// Mounts and commences playback for the specified media item using an explicit player engine.
    ///
    /// - Parameters:
    ///   - item: The target media item.
    ///   - preferredKind: Optional engine kind override (`.native` or `.extended`). If `nil`, standard format detection is used.
    public func setupPlayer(for item: MediaItem, preferredEngine preferredKind: PlayerEngineKind? = nil) {
        playbackStartTime = Date()
        didRestorePlaybackPosition = false
        restoredFromSeconds = nil
        currentPlaybackSeconds = 0
        totalDurationSeconds = 0
        tearDownPlayer(deactivateAudioSession: false)
        currentlyLoadedItem = item
        showControls = true
        playbackState = .loading
        errorMessage = nil
        
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
            } catch {
                loge("Failed to activate audio session: \(error.localizedDescription)")
            }
        }
        
        let ext = (item.name as NSString).pathExtension
        let isExtended = preferredKind.map { $0 == .extended } ?? SupportedMediaTypes.isExtendedVideo(extension: ext)
        
        // 1. If local file or cached locally, play immediately from file
        if let localURL = item.localURL ?? (MediaCacheManager.shared.hasCachedVideo(for: item) ? MediaCacheManager.shared.localVideoURL(for: item) : nil) {
            self.shareableVideoURL = localURL
            if isExtended {
                setupExtendedEngine(with: localURL, for: item)
                return
            }
            
            setupNativeEngine(with: AVPlayerItem(url: localURL), for: item, isRemoteStream: false)
            return
        }
        
        // 2. Apple Photos Library Video or Progressive On-Demand SMB Stream
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if item.phAssetIdentifier != nil {
                do {
                    let videoURL = try await manager.fetchVideoURL(for: item)
                    guard !Task.isCancelled else { return }
                    self.shareableVideoURL = videoURL
                    if isExtended {
                        self.setupExtendedEngine(with: videoURL, for: item)
                    } else {
                        self.setupNativeEngine(with: AVPlayerItem(url: videoURL), for: item, isRemoteStream: false)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    self.presentPlaybackError(error.localizedDescription)
                }
                return
            }
            
            let validItem = await manager.resolveValidItem(for: item)
            guard !Task.isCancelled else { return }
            
            if isExtended {
                guard await self.manager.clientActor.activeClient() != nil else {
                    let desc = String(localized: .Strings.videoPlayerErrorInvalidStreamUrl)
                    self.errorMessage = desc
                    self.playbackState = .failed(desc)
                    return
                }
                
                self.engineKind = .extended
                self.player = nil
                self.playbackState = .buffering
                
                if let server = await self.manager.clientActor.activeServerConnection(),
                   let smbURL = VLCPlaybackOptions.makeSMBURL(
                       host: server.host,
                       share: validItem.shareName,
                       relativePath: validItem.smbRelativePath
                   ) {
                    let password = await self.manager.password(for: server)
                    let options = VLCPlaybackOptions(
                        username: server.username,
                        password: password
                    )
                    self.setupExtendedEngine(with: smbURL, for: validItem, options: options)
                    return
                }

                guard !Task.isCancelled else { return }
                self.presentPlaybackError("Unable to construct direct SMB playback URL for extended video format.")
                return
            }
            
            self.engineKind = .native
            let streamURL = SMBAVAssetResourceLoaderDelegate.makeStreamURL(fileName: validItem.name)
            guard validItem.size > 0,
                  streamURL.scheme == SMBAVAssetResourceLoaderDelegate.scheme,
                  let client = await self.manager.clientActor.activeClient() else {
                let desc = String(localized: .Strings.videoPlayerErrorInvalidStreamUrl)
                self.errorMessage = desc
                self.playbackState = .failed(desc)
                return
            }
            
            let asset = AVURLAsset(url: streamURL)
            self.currentAsset = asset
            let delegate = SMBAVAssetResourceLoaderDelegate(
                client: client,
                share: validItem.shareName,
                path: validItem.smbRelativePath,
                fileName: validItem.name,
                fileSize: validItem.size,
                chunkSize: 512 * 1024
            )
            self.loaderDelegate = delegate
            
            // AVAssetResourceLoader requires a GCD queue for delegate callbacks (no async API
            // exists). The delegate is retained in `loaderDelegate` because the asset only holds it weakly.
            // swiftlint:disable:next no_legacy_dispatch_queue
            let queue = DispatchQueue(label: "com.acme.ios.photos.videoloader.\(UUID().uuidString)", qos: .userInitiated)
            asset.resourceLoader.setDelegate(delegate, queue: queue)
            
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 2.0
            self.setupNativeEngine(with: playerItem, for: validItem, isRemoteStream: true)
        }
    }
    
    /// Switches between Native (`AVPlayerEngine`) and VLC (`TVVLCPlayerEngine`) playback backends,
    /// starting at the beginning of the video and clearing any saved resume progress.
    public func switchEngine() {
        let targetItem = currentlyLoadedItem ?? currentItem
        VideoPlaybackStore.shared.clearPosition(for: targetItem)
        let nextKind: PlayerEngineKind = (engineKind == .native) ? .extended : .native
        setupPlayer(for: targetItem, preferredEngine: nextKind)
    }
    
    /// Configures and mounts the native `AVPlayerEngine` for system-supported media items.
    private func setupNativeEngine(
        with playerItem: AVPlayerItem,
        for item: MediaItem,
        isRemoteStream: Bool
    ) {
        self.engineKind = .native
        self.trackManager.reset()
        
        let avPlayer = AVPlayer()
        if isRemoteStream {
            avPlayer.automaticallyWaitsToMinimizeStalling = true
        }
        self.player = avPlayer
        
        let native = AVPlayerEngine(player: avPlayer)
        self.nativeEngine = native
        self.engine = native
        
        configureCallbacks(for: native, playerItem: playerItem, item: item)
        
        self.volume = native.volume
        self.isMuted = native.isMuted
        native.playbackRate = trackManager.playbackRate.rawValue
        avPlayer.defaultRate = trackManager.playbackRate.rawValue
        
        native.load(playerItem: playerItem)
        let knownDuration = playerItem.duration.seconds
        restorePlaybackPosition(for: item, knownDuration: knownDuration) { savedSeconds in
            native.seek(to: savedSeconds, toleranceBefore: 0, toleranceAfter: 0, completion: nil)
        }
        
        if !isRemoteStream {
            Task { @MainActor [weak self] in
                await self?.trackManager.loadTracks(for: playerItem)
            }
        }
        
        native.play()
        if case .failed = native.playbackState {
            return
        }
        if isRemoteStream && avPlayer.timeControlStatus != .playing {
            self.playbackState = .buffering
        } else {
            self.playbackState = native.playbackState
            self.scheduleControlsAutoHide()
        }
    }
    
    /// Configures and mounts the extended `TVVLCPlayerEngine` for open video containers and codecs.
    private func setupExtendedEngine(
        with url: URL,
        for item: MediaItem,
        options: VLCPlaybackOptions? = nil
    ) {
        self.engineKind = .extended
        self.player = nil
        self.trackManager.reset()
        
        let extended = TVVLCPlayerEngine()
        configureCallbacks(for: extended, item: item)
        self.extendedEngine = extended
        self.engine = extended
        
        extended.volume = self.volume
        extended.isMuted = self.isMuted
        extended.playbackRate = trackManager.playbackRate.rawValue
        
        var startPosition: Double = 0
        self.restorePlaybackPosition(for: item, knownDuration: nil) { savedSeconds in
            startPosition = savedSeconds
        }
        extended.load(url: url, startPosition: startPosition, options: options)
        extended.play()
        if case .failed = extended.playbackState {
            return
        }
        self.playbackState = extended.isPlaying ? .playing : .buffering
        self.scheduleControlsAutoHide()
    }
    
    /// Wires `AVPlayerEngine` event callbacks into controller state and `VideoTrackManager`.
    private func configureCallbacks(for native: AVPlayerEngine, playerItem: AVPlayerItem, item: MediaItem) {
        native.onTimeUpdate = { [weak self] time in
            self?.handleEngineTimeUpdate(time, for: item)
        }
        native.onDurationUpdate = { [weak self] duration in
            self?.handleEngineDurationUpdate(duration)
        }
        native.onStateUpdate = { [weak self] state in
            self?.handleEngineStateUpdate(state)
        }
        native.onTracksChanged = { [weak self, weak playerItem] in
            guard let self, let playerItem, playerItem.status == .readyToPlay else { return }
            Task { @MainActor [weak self] in
                await self?.trackManager.loadTracks(for: playerItem)
            }
        }
        native.onChaptersChanged = { [weak self, weak native] in
            guard let self, let native else { return }
            self.availableChapters = native.availableChapters
        }
        native.onError = { [weak self] error in
            self?.presentPlaybackError(error.localizedDescription)
        }
        native.onPlaybackEnded = { [weak self] in
            self?.handlePlaybackCompletion()
        }
    }
    
    /// Wires `TVVLCPlayerEngine` event callbacks into controller state and `VideoTrackManager`.
    private func configureCallbacks(for extended: TVVLCPlayerEngine, item: MediaItem) {
        extended.onTimeUpdate = { [weak self] time in
            self?.handleEngineTimeUpdate(time, for: item)
        }
        extended.onDurationUpdate = { [weak self] duration in
            self?.handleEngineDurationUpdate(duration)
        }
        extended.onStateUpdate = { [weak self] state in
            self?.handleEngineStateUpdate(state)
        }
        extended.onTracksChanged = { [weak self, weak extended] in
            guard let self, let extended else { return }
            self.trackManager.loadTracks(for: extended)
            self.availableChapters = extended.availableChapters
        }
        extended.onChaptersChanged = { [weak self, weak extended] in
            guard let self, let extended else { return }
            self.availableChapters = extended.availableChapters
        }
        extended.onError = { [weak self] error in
            self?.presentPlaybackError(error.localizedDescription)
        }
        extended.onPlaybackEnded = { [weak self] in
            self?.handlePlaybackCompletion()
        }
    }
    
    private func handleEngineTimeUpdate(_ time: Double, for item: MediaItem) {
        let isExtendedScrubbing = extendedEngine?.isScrubbing ?? false
        if !seekCoordinator.isScrubbing && !isExtendedScrubbing && time.isFinite && !time.isNaN {
            currentPlaybackSeconds = time
        }
        
        if totalDurationSeconds <= 0,
           let itemDuration = nativeEngine?.avPlayer.currentItem?.duration.seconds,
           itemDuration.isFinite && !itemDuration.isNaN && itemDuration > 0 {
            totalDurationSeconds = itemDuration
        }
        
        if didRestorePlaybackPosition, let restored = restoredFromSeconds, abs(time - restored) > 2.5 {
            didRestorePlaybackPosition = false
            restoredFromSeconds = nil
        }
        
        if engineKind == .extended, playbackState.isBuffering, engine?.isPlaying == true {
            withAnimation(.easeInOut(duration: 0.2)) {
                playbackState = .playing
            }
            scheduleControlsAutoHide()
        }
        
        if !seekCoordinator.isScrubbing && !isExtendedScrubbing,
           time.isFinite && !time.isNaN,
           totalDurationSeconds.isFinite && !totalDurationSeconds.isNaN && totalDurationSeconds > 0,
           time >= 2.0 {
            VideoPlaybackStore.shared.savePosition(time, duration: totalDurationSeconds, for: item)
        }
    }
    
    private func handleEngineDurationUpdate(_ duration: Double) {
        guard duration.isFinite && !duration.isNaN && duration >= 0 else { return }
        totalDurationSeconds = duration
        if let saved = restoredFromSeconds, duration > 0 {
            if saved >= duration - 4.0 || saved / duration >= 0.90 {
                restartVideo()
            }
        }
    }
    
    private func handleEngineStateUpdate(_ state: PlayerPlaybackState) {
        let wasPlaying = playbackState.isPlaying
        if case .failed(let message) = state {
            presentPlaybackError(message)
            return
        }
        if seekCoordinator.isFinishingSeek && state == .paused {
            return
        }
        if playbackState != state {
            withAnimation(.easeInOut(duration: 0.2)) {
                playbackState = state
            }
        }
        if state.isBuffering && !seekCoordinator.isScrubbing {
            cancelAutoHideTimer()
        } else if !wasPlaying && state.isPlaying {
            scheduleControlsAutoHide()
        } else if showControls && state.isPlaying && hideControlsTask == nil && !seekCoordinator.isScrubbing {
            scheduleControlsAutoHide()
        }
    }
    
    private func presentPlaybackError(_ rawDescription: String) {
        let sanitized = sanitizeErrorDescription(rawDescription)
        let localizedDesc = String(localized: .Strings.videoPlayerErrorPlayback(sanitized))
        errorMessage = localizedDesc
        playbackState = .failed(localizedDesc)
    }
    
    #if DEBUG
    /// Simulates an abrupt crash (SIGABRT) during media playback for diagnostics and crash reporting testing.
    public func simulateSMBDisconnectCrash() {
        logw("Simulating abrupt crash (SIGABRT)...")
        Darwin.raise(SIGABRT)
    }
    #endif
    
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
    
    private var lastControlsToggleTime: Date = .distantPast
    
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
    
    /// Tears down the active player instance, flushing saved progress and cancelling in-flight tasks.
    ///
    /// - Parameter deactivateAudioSession: Whether to release the system audio session.
    public func tearDownPlayer(deactivateAudioSession: Bool = false) {
        if let currentEngine = engine, let loadedItem = currentlyLoadedItem {
            let secs = currentEngine.currentTime
            let engineDur = currentEngine.duration
            let dur = engineDur > 0 ? engineDur : totalDurationSeconds
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
        resumeBannerTask?.cancel()
        resumeBannerTask = nil
        resumedToastMessage = nil
        availableChapters = []
        trackManager.reset()
        
        hideControlsTask?.cancel()
        hideControlsTask = nil
        seekCoordinator.reset()
        loadTask?.cancel()
        loadTask = nil
        saveTask?.cancel()
        saveTask = nil
        loaderDelegate?.cancelAll()
        loaderDelegate = nil
        currentAsset?.resourceLoader.setDelegate(nil, queue: nil)
        currentAsset = nil
        
        clearCallbacks(for: extendedEngine)
        extendedEngine?.tearDown()
        extendedEngine = nil
        
        clearCallbacks(for: nativeEngine)
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
    
    private func clearCallbacks(for native: AVPlayerEngine?) {
        native?.onPlaybackEnded = nil
        native?.onError = nil
        native?.onStateUpdate = nil
        native?.onTimeUpdate = nil
        native?.onDurationUpdate = nil
        native?.onTracksChanged = nil
        native?.onChaptersChanged = nil
    }
    
    private func clearCallbacks(for extended: TVVLCPlayerEngine?) {
        extended?.onPlaybackEnded = nil
        extended?.onError = nil
        extended?.onStateUpdate = nil
        extended?.onTimeUpdate = nil
        extended?.onDurationUpdate = nil
        extended?.onTracksChanged = nil
        extended?.onChaptersChanged = nil
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
