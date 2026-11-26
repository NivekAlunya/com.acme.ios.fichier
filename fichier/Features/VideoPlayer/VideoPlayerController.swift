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
    public var showControls: Bool = false
    
    /// Indicates whether Picture-in-Picture presentation is actively running.
    public var isPiPActive: Bool = false {
        didSet {
            if !isPiPActive && hasDisappeared {
                tearDownPlayer(deactivateAudioSession: true)
            }
        }
    }

    /// Tracks whether the hosting player view has disappeared while PiP remained active.
    public internal(set) var hasDisappeared: Bool = false
    
    /// Coordinator managing Picture-in-Picture lifecycle and delegate callbacks.
    public let pipCoordinator = CustomVideoPlayerCoordinator()
    
    /// Manager handling audio tracks, subtitle streams, and playback speed.
    public let trackManager = VideoTrackManager()
    
    /// Available chapter markers parsed from the active media item.
    public private(set) var availableChapters: [PlayerChapter] = []
    
    /// Coordinator managing timeline scrubbing, live frame seeking, and debounce timers.
    public let seekCoordinator = VideoSeekCoordinator()
    
    /// Coordinator managing downloading and saving video files to the system Photos library.
    public let cameraRollExporter = VideoCameraRollExporter()

    /// Indicates whether export to Camera Roll is actively in flight.
    public var isSaving: Bool {
        get { cameraRollExporter.isSaving }
        set { cameraRollExporter.isSaving = newValue }
    }
    
    /// Temporary toast message displayed after saving to Camera Roll.
    public var saveStatusMessage: String? {
        get { cameraRollExporter.saveStatusMessage }
        set { cameraRollExporter.saveStatusMessage = newValue }
    }
    
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
    
    var hideControlsTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var folderIconTask: Task<Void, Never>?
    var resumeBannerTask: Task<Void, Never>?
    var lastControlsToggleTime: Date = .distantPast

    isolated deinit {
        loadTask?.cancel()
        folderIconTask?.cancel()
        hideControlsTask?.cancel()
        resumeBannerTask?.cancel()
        loaderDelegate?.cancelAll()
        currentAsset?.resourceLoader.setDelegate(nil, queue: nil)
    }
    
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
        
        // Link video thumbnail as the folder's video icon when played
        folderIconTask?.cancel()
        folderIconTask = Task(priority: .utility) { [weak self] in
            guard let self, !Task.isCancelled else { return }
            if let thumb = await self.manager.downloadThumbnail(for: item) {
                guard !Task.isCancelled else { return }
                MediaCacheManager.shared.linkFolderIcon(
                    thumb,
                    childPath: item.path,
                    shareName: item.shareName,
                    connectionID: item.connectionID,
                    isVideo: true
                )
            }
        }
        
        VideoAudioSessionCoordinator.enqueuePlaybackSessionActivation()
        
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
                    guard !Task.isCancelled else { return }
                    let options = VLCPlaybackOptions(
                        username: server.username,
                        password: password
                    )
                    self.setupExtendedEngine(with: smbURL, for: validItem, options: options)
                    return
                }

                guard !Task.isCancelled else { return }
                self.presentPlaybackError(String(localized: .Strings.videoPlayerErrorExtendedFormat))
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
            asset.resourceLoader.setDelegate(delegate, queue: FichierResourceLoaderQueue.shared)
            
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
        pipCoordinator.reset()
        isPiPActive = false
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
        extended.onPiPStatusChanged = { [weak self] isActive in
            self?.isPiPActive = isActive
        }
    }

    /// Toggles Picture-in-Picture presentation for the currently active playback engine.
    public func togglePiP() {
        switch engineKind {
        case .native:
            pipCoordinator.togglePiP()
        case .extended:
            extendedEngine?.togglePiP()
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
    
    func presentPlaybackError(_ rawDescription: String) {
        let sanitized = VideoPlayerErrorSanitizer.sanitize(rawDescription)
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

    /// Tears down the active player instance, flushing saved progress and cancelling in-flight tasks.
    ///
    /// - Parameter deactivateAudioSession: Whether to release the system audio session.
    public func tearDownPlayer(deactivateAudioSession: Bool = false) {
        hasDisappeared = false
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
        folderIconTask?.cancel()
        folderIconTask = nil
        cameraRollExporter.cancel()
        loaderDelegate?.cancelAll()
        loaderDelegate = nil
        currentAsset?.resourceLoader.setDelegate(nil, queue: nil)
        currentAsset = nil
        
        clearCallbacks(for: engine)
        extendedEngine?.tearDown()
        extendedEngine = nil
        nativeEngine?.tearDown()
        nativeEngine = nil
        engine = nil
        
        player?.pause()
        player = nil
        pipCoordinator.reset()
        isPiPActive = false
        playbackState = .idle
        errorMessage = nil
        
        if deactivateAudioSession {
            VideoAudioSessionCoordinator.enqueueSessionDeactivation()
        }
    }
    
    private func clearCallbacks(for engine: (any PlayerEngine)?) {
        engine?.clearCallbacks()
    }
}
