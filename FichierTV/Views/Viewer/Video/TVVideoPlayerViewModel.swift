//
//  TVVideoPlayerViewModel.swift
//  FichierTV
//
//

import SwiftUI
import Observation
import AVFoundation
import os
import FichierKit

/// Master state coordinator for the tvOS video player, handling dual playback engines (`AVPlayerEngine` and `TVVLCPlayerEngine`),
/// PhotoKit and SMB video resolution, Siri Remote scrubbing acceleration, multi-tiered Menu back handling, resume-playback, and auto-hide.
@Observable
@MainActor
public final class TVVideoPlayerViewModel {
    private static let logger = Logger(subsystem: "com.acme.ios.fichiertv", category: "videoPlayerViewModel")

    public private(set) var videos: [MediaSourceItem]
    public private(set) var currentIndex: Int
    private let paginationContext: TVViewerPaginationContext?
    private var paginationSource: (any MediaSource)?
    private var nextPageToFetch: Int
    private var hasMoreSourcePages: Bool
    private var seenItemIDs: Set<String>
    private var paginationTask: Task<Void, Never>?

    public var canPlayPrevious: Bool {
        currentIndex > 0
    }

    public var canPlayNext: Bool {
        currentIndex < videos.count - 1 || hasMoreSourcePages
    }

    public let nativeEngine: AVPlayerEngine
    public let extendedEngine: TVVLCPlayerEngine
    public private(set) var activeEngine: any PlayerEngine
    public private(set) var activeEngineKind: PlayerEngineKind = .native

    public private(set) var playbackState: PlayerPlaybackState = .idle
    public private(set) var currentTime: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var isPlaying: Bool = false
    public private(set) var availableAudioTracks: [PlayerAudioTrack] = []
    public private(set) var selectedAudioTrack: PlayerAudioTrack?
    public private(set) var availableSubtitleTracks: [PlayerSubtitleTrack] = []
    public private(set) var selectedSubtitleTrack: PlayerSubtitleTrack?
    public private(set) var availableChapters: [PlayerChapter] = []
    public private(set) var playbackRate: TVVideoPlaybackRate = .normal
    public var isPiPActive: Bool = false {
        didSet {
            if !isPiPActive && hasDisappeared {
                tearDown()
            }
        }
    }
    public private(set) var hasDisappeared: Bool = false
    public let pipCoordinator = TVVideoPictureInPictureCoordinator()

    public var showOverlay: Bool = false
    public var activeFocusRow: TVVideoPlayerFocusRow = .buttons
    public var activeFocusedButton: TVVideoPlayerButtonKind = .playPause
    public let thumbnailCoordinator: TVVideoSeekThumbnailCoordinator
    public let remoteSeekCoordinator: TVVideoRemoteSeekCoordinator

    public var isScrubbing: Bool {
        get { remoteSeekCoordinator.isScrubbing }
        set { remoteSeekCoordinator.isScrubbing = newValue }
    }
    public var scrubbingTime: Double? {
        get { remoteSeekCoordinator.scrubbingTime }
        set { remoteSeekCoordinator.scrubbingTime = newValue }
    }

    public private(set) var errorMessage: String?
    public var isShowingChaptersSheet: Bool = false
    public var isShowingTracksSheet: Bool = false
    public var isShowingSpeedSheet: Bool = false

    public var remoteSeekPreview: TVRemoteSeekPreview? {
        remoteSeekCoordinator.remoteSeekPreview
    }
    public var seekThumbnailState: TVSeekThumbnailState? {
        get { thumbnailCoordinator.seekThumbnailState }
        set { thumbnailCoordinator.seekThumbnailState = newValue }
    }

    public var isRemoteSeekHolding: Bool {
        remoteSeekCoordinator.isRemoteSeekHolding
    }
    var activeRemoteSeekHold: TVRemoteSeekHoldState? {
        remoteSeekCoordinator.activeRemoteSeekHold
    }

    private let playbackStore: any VideoPlaybackStoreProtocol
    private let resolver: any MediaSourceResolverProtocol
    private let remoteCommandBridge: any TVRemoteCommandHandling
    private let thumbnailProvider: any TVSeekThumbnailProviding
    private let uptimeProvider: @MainActor @Sendable () -> TimeInterval
    private var autoHideTask: Task<Void, Never>?
    private var progressPersistenceTask: Task<Void, Never>?
    private var mediaLoadTask: Task<Void, Never>?
    private var playbackPositionRestoreTask: Task<Void, Never>?
    private var resolvedMediaURL: URL?
    private var directSMBURL: URL?
    private var vlcPlaybackOptions: VLCPlaybackOptions?
    private var smbResourceLoaderDelegate: SMBAVAssetResourceLoaderDelegate?
    private var hasAttemptedFallback: Bool = false
    private var isRemoteCommandBridgeActive: Bool = false
    private var lastLocalPlayPauseUptime: TimeInterval?
    private var lastPublishedNowPlayingTime: Double = -10

    public var currentItem: MediaSourceItem {
        guard !videos.isEmpty, currentIndex >= 0, currentIndex < videos.count else {
            return MediaSourceItem(id: "empty", name: "", path: "", type: .video)
        }
        return videos[currentIndex]
    }

    public var currentFocusTarget: TVVideoOverlayFocusTarget {
        if activeFocusRow == .progress {
            return .progress
        }
        switch activeFocusedButton {
        case .previous:
            return .previous
        case .playPause:
            return .playPause
        case .next:
            return .next
        case .switchEngine:
            return .switchEngine
        case .chapters:
            return .chapters
        case .tracks:
            return .tracks
        case .speed:
            return .speed
        case .pip:
            return .pip
        }
    }

    public init(
        initialItem: MediaSourceItem,
        videos: [MediaSourceItem],
        paginationContext: TVViewerPaginationContext? = nil,
        playbackStore: any VideoPlaybackStoreProtocol = VideoPlaybackStore.shared,
        resolver: any MediaSourceResolverProtocol = DefaultMediaSourceResolver.shared,
        remoteCommandBridge: any TVRemoteCommandHandling = TVSystemRemoteCommandBridge(),
        thumbnailProvider: any TVSeekThumbnailProviding = TVSeekThumbnailService(),
        uptimeProvider: @escaping @MainActor @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        let filteredVideos = videos.filter { $0.type == .video }
        let resolvedVideos = filteredVideos.isEmpty ? [initialItem] : filteredVideos
        self.videos = resolvedVideos
        self.currentIndex = resolvedVideos.firstIndex(where: { $0.id == initialItem.id }) ?? 0
        self.paginationContext = paginationContext
        self.nextPageToFetch = paginationContext?.nextPage ?? 0
        self.hasMoreSourcePages = paginationContext?.canLoadMore ?? false
        self.seenItemIDs = Set(resolvedVideos.map(\.id))

        let native = AVPlayerEngine()
        let extended = TVVLCPlayerEngine()
        self.nativeEngine = native
        self.extendedEngine = extended
        self.activeEngine = native
        self.playbackStore = playbackStore
        self.resolver = resolver
        self.remoteCommandBridge = remoteCommandBridge
        self.thumbnailProvider = thumbnailProvider
        self.uptimeProvider = uptimeProvider

        let thumbCoord = TVVideoSeekThumbnailCoordinator(thumbnailProvider: thumbnailProvider)
        let seekCoord = TVVideoRemoteSeekCoordinator(uptimeProvider: uptimeProvider)
        self.thumbnailCoordinator = thumbCoord
        self.remoteSeekCoordinator = seekCoord

        seekCoord.currentDurationProvider = { [weak self] in self?.duration ?? 0 }
        seekCoord.currentTimeProvider = { [weak self] in self?.currentTime ?? 0 }
        seekCoord.onCommitSeek = { [weak self] target, timestamp in
            guard let self else { return }
            self.commitRemoteSeek(to: target, at: timestamp)
        }
        seekCoord.onRequestThumbnail = { [weak self] target in
            self?.requestSeekThumbnail(for: target)
        }
        seekCoord.onCancelThumbnails = { [weak self] clearState in
            self?.thumbnailCoordinator.cancelSeekThumbnails(clearState: clearState)
        }
        seekCoord.onResetInactivityTimer = { [weak self] in
            self?.resetInactivityTimer()
        }

        setupEngineCallbacks()
    }

    /// Mounts and commences playback for the current video item (local, PhotoKit, or SMB stream).
    ///
    /// - Parameter preferredEngine: Optional engine kind override (`.native` or `.extended`).
    public func loadCurrentVideo(preferredEngine: PlayerEngineKind? = nil) {
        errorMessage = nil
        hasAttemptedFallback = false
        resolvedMediaURL = nil
        directSMBURL = nil
        vlcPlaybackOptions = nil
        availableChapters = []
        clearRemoteSeekState()
        resetCachedSeekThumbnails()
        lastPublishedNowPlayingTime = -10
        activateRemoteCommandBridgeIfNeeded()

        mediaLoadTask?.cancel()
        mediaLoadTask = nil
        playbackPositionRestoreTask?.cancel()
        playbackPositionRestoreTask = nil
        progressPersistenceTask?.cancel()
        progressPersistenceTask = nil
        autoHideTask?.cancel()
        autoHideTask = nil

        smbResourceLoaderDelegate?.cancelAll()
        smbResourceLoaderDelegate = nil

        activeEngine.tearDown()

        let item = currentItem
        let initialKind = preferredEngine ?? preferredEngineKind(for: item)
        setActiveEngine(kind: initialKind)

        // Link video thumbnail as the folder's video icon when played
        let playedItem = item
        Task(priority: .utility) {
            let targetSize = CGSize(width: 440, height: 260)
            let thumb: UIImage?
            if let phID = playedItem.phAssetIdentifier {
                thumb = await PhotoThumbnailLoader.shared.loadThumbnail(for: phID, targetSize: targetSize)
            } else if let localURL = playedItem.localURL, localURL.isFileURL {
                thumb = await SMBVideoThumbnailLoader.shared.loadThumbnail(
                    from: localURL,
                    fileName: playedItem.name,
                    targetSize: targetSize
                )
            } else if let sourceID = playedItem.sourceID,
                      let share = playedItem.smbShare,
                      let path = playedItem.smbPath {
                thumb = await SMBVideoThumbnailLoader.shared.loadThumbnail(
                    sourceID: sourceID,
                    share: share,
                    path: path,
                    fileName: playedItem.name,
                    fileSize: playedItem.size,
                    targetSize: targetSize
                )
            } else {
                thumb = nil
            }
            if let thumb {
                playedItem.linkThumbnailAsFolderIcon(thumb)
            }
        }

        if let localURL = item.localURL {
            resolvedMediaURL = localURL
            mount(url: localURL, kind: initialKind)
        } else if let phID = item.phAssetIdentifier {
            loadPhotoKitVideo(assetIdentifier: phID, itemID: item.id, preferredKind: initialKind)
        } else if item.sourceID != nil, item.smbShare != nil, item.smbPath != nil {
            loadSMBVideo(item: item, preferredKind: initialKind)
        } else {
            let errorDesc = String(localized: .Strings.videoPlayerErrorLocateSource(item.name))
            playbackState = .failed(errorDesc)
            errorMessage = errorDesc
        }
    }

    /// Switches between native AVPlayer and extended VLC playback engines, starting from the beginning
    /// of the video and clearing saved resume progress.
    public func switchEngine() {
        let nextKind: PlayerEngineKind = (activeEngineKind == .native) ? .extended : .native
        let itemID = currentItem.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.playbackStore.clearPlaybackPosition(for: itemID)
            guard !Task.isCancelled, self.currentItem.id == itemID else { return }
            self.loadCurrentVideo(preferredEngine: nextKind)
        }
    }

    /// Determines preferred engine before attempting playback.
    public func preferredEngineKind(for item: MediaSourceItem) -> PlayerEngineKind {
        if item.phAssetIdentifier != nil {
            return .native
        }
        let ext = (item.name as NSString).pathExtension.lowercased()
        return SupportedMediaTypes.isExtendedVideo(extension: ext) ? .extended : .native
    }

    // MARK: - Remote Navigation & Input Handling

    /// Reveals the HUD overlay if hidden and resets auto-hide timing.
    public func revealOverlay() {
        resetInactivityTimer()
        if let hold = remoteSeekCoordinator.activeRemoteSeekHold {
            cancelRemoteSeek(isForward: hold.isForward, source: hold.source)
        }
        guard !showOverlay else { return }
        withAnimation(.snappy) {
            showOverlay = true
        }
    }

    /// Synchronizes ViewModel row/button focus tracking with native tvOS Focus Engine changes.
    public func syncFocusTarget(_ target: TVVideoOverlayFocusTarget?) {
        resetInactivityTimer()
        guard let target else { return }

        if target != .progress && isScrubbing {
            cancelScrub()
        }

        switch target {
        case .progress:
            activeFocusRow = .progress
        case .previous:
            activeFocusRow = .buttons
            activeFocusedButton = .previous
        case .playPause:
            activeFocusRow = .buttons
            activeFocusedButton = .playPause
        case .next:
            activeFocusRow = .buttons
            activeFocusedButton = .next
        case .switchEngine:
            activeFocusRow = .buttons
            activeFocusedButton = .switchEngine
        case .chapters:
            activeFocusRow = .buttons
            activeFocusedButton = .chapters
        case .tracks:
            activeFocusRow = .buttons
            activeFocusedButton = .tracks
        case .speed:
            activeFocusRow = .buttons
            activeFocusedButton = .speed
        case .pip:
            activeFocusRow = .buttons
            activeFocusedButton = .pip
        }
    }

    /// Steps accelerated scrubbing forward or backward when the progress scrubber has focus.
    public func stepScrub(forward: Bool) {
        activeFocusRow = .progress
        resetInactivityTimer()
        adjustScrub(forward: forward)
    }

    /// Applies continuous horizontal swipe deltas from the Siri Remote touchpad when the HUD scrubber has focus.
    public func updateSwipeScrub(translationDeltaX: Double, velocityX: Double, trackWidth: Double) {
        guard duration > 0 else { return }
        activeFocusRow = .progress
        resetInactivityTimer()

        let delta = TVRemoteSeekCalculator.swipeScrubDelta(
            translationDeltaX: translationDeltaX,
            velocityX: velocityX,
            trackWidth: trackWidth,
            totalDuration: duration
        )
        guard delta.isFinite && !delta.isNaN else { return }

        let baseTime = scrubbingTime ?? currentTime
        let clampedTarget = max(0, min(duration, baseTime + delta))
        isScrubbing = true
        scrubbingTime = clampedTarget
        requestSeekThumbnail(for: clampedTarget)
    }

    /// Completes an active touchpad swipe gesture while leaving the scrubbed timestamp parked until Select/Menu.
    public func finishSwipeScrubInteraction() {
        resetInactivityTimer()
    }

    /// Commits pending scrub seek when scrubbing, or toggles playback otherwise.
    public func activateScrubberSelect() {
        resetInactivityTimer()
        if isScrubbing {
            commitScrub()
        } else {
            togglePlayPause()
        }
    }

    /// Presents the Chapters & Quick Jump sheet while pausing overlay auto-hide.
    public func openChaptersMenu() {
        autoHideTask?.cancel()
        isShowingChaptersSheet = true
    }

    /// Jumps directly to a target chapter or quick-jump timestamp using fast keyframe seeking.
    public func jumpToTime(_ targetSeconds: Double) {
        guard targetSeconds.isFinite && !targetSeconds.isNaN else { return }
        let upperBound = duration > 0 ? duration : max(0, targetSeconds)
        let clamped = max(0, min(upperBound, targetSeconds))
        let delta = clamped - currentTime

        clearRemoteSeekState()
        cancelSeekThumbnails(clearState: true)

        let timestamp = uptimeProvider()
        commitRemoteSeek(to: clamped, at: timestamp)
        remoteSeekCoordinator.presentRemoteSeekPreview(
            TVRemoteSeekPreview(targetTime: clamped, deltaSeconds: delta, isHolding: false)
        )
    }

    /// Presents the Audio & Subtitles track selection sheet while pausing overlay auto-hide.
    public func openTracksMenu() {
        autoHideTask?.cancel()
        isShowingTracksSheet = true
    }

    /// Presents the Playback Speed selection sheet while pausing overlay auto-hide.
    public func openSpeedMenu() {
        autoHideTask?.cancel()
        isShowingSpeedSheet = true
    }

    /// Updates the playback speed multiplier across both native and extended playback engines.
    public func selectPlaybackRate(_ rate: TVVideoPlaybackRate) {
        resetInactivityTimer()
        playbackRate = rate
        nativeEngine.playbackRate = rate.rawValue
        extendedEngine.playbackRate = rate.rawValue
    }

    /// Processes directional D-pad input from the Siri Remote.
    public func handleDirectionalInput(direction: MoveCommandDirection) {
        resetInactivityTimer()

        // Section 6: First directional press only reveals hidden overlay
        guard showOverlay else {
            withAnimation(.snappy) {
                showOverlay = true
            }
            return
        }

        switch direction {
        case .up:
            activeFocusRow = .progress
        case .down:
            activeFocusRow = .buttons
        case .left:
            if activeFocusRow == .progress {
                adjustScrub(forward: false)
            } else {
                moveButtonFocus(forward: false)
            }
        case .right:
            if activeFocusRow == .progress {
                adjustScrub(forward: true)
            } else {
                moveButtonFocus(forward: true)
            }
        @unknown default:
            break
        }
    }

    /// Processes the Siri Remote Select button.
    public func handleSelect() {
        resetInactivityTimer()

        // Section 6: First Select press only reveals hidden overlay
        guard showOverlay else {
            withAnimation(.snappy) {
                showOverlay = true
            }
            return
        }

        if activeFocusRow == .progress && isScrubbing {
            commitScrub()
        } else if activeFocusRow == .buttons {
            activateFocusedButton()
        }
    }

    /// Multi-tiered Menu back button handler:
    /// 1. Cancel an active `<<`/`>>` remote hold without seeking
    /// 2. Cancel scrub if scrubbing
    /// 3. Hide overlay if visible
    /// 4. Returns `false` to permit `NavigationStack` pop
    public func handleMenuPress() -> Bool {
        resetInactivityTimer()

        if let hold = remoteSeekCoordinator.activeRemoteSeekHold, !hold.wasCancelledByMenu {
            remoteSeekCoordinator.cancelActiveRemoteSeekHoldByMenu()
            cancelSeekThumbnails(clearState: true)
            return true
        }

        if isScrubbing {
            cancelScrub()
            return true
        }

        if showOverlay {
            withAnimation(.snappy) {
                showOverlay = false
            }
            return true
        }

        return false
    }

    /// Begins tracking a `<<` / `>>` press-and-release seek gesture from Siri Remote or hardware remote commands.
    public func beginRemoteSeek(
        isForward: Bool,
        source: TVRemoteSeekSource,
        timestamp: TimeInterval? = nil
    ) {
        guard errorMessage == nil, !videos.isEmpty else { return }
        autoHideTask?.cancel()
        remoteSeekCoordinator.beginRemoteSeek(isForward: isForward, source: source, timestamp: timestamp)
    }

    /// Completes a `<<` / `>>` press gesture as a tap (`±15s`), double-tap within `0.50s` (`±60s`),
    /// or progressive hold multiplier seek (`>= 0.30s`).
    public func endRemoteSeek(
        isForward: Bool,
        source: TVRemoteSeekSource,
        timestamp: TimeInterval? = nil
    ) {
        remoteSeekCoordinator.endRemoteSeek(isForward: isForward, source: source, timestamp: timestamp)
    }

    /// Cancels an active press gesture without seeking playback (for example when UIKit cancels a press).
    public func cancelRemoteSeek(isForward: Bool, source: TVRemoteSeekSource) {
        remoteSeekCoordinator.cancelRemoteSeek(isForward: isForward, source: source)
    }

    /// Executes an immediate discrete `±15s` tap (upgrading to `±60s` total on a second tap within `0.50s`).
    public func triggerRemoteTapSkip(isForward: Bool, timestamp: TimeInterval? = nil) {
        guard errorMessage == nil, !videos.isEmpty else { return }
        remoteSeekCoordinator.triggerRemoteTapSkip(isForward: isForward, timestamp: timestamp)
    }

    /// Updates live preview state when an active hold has crossed the hold threshold (exposed for tests and 20 Hz loop).
    public func refreshActiveRemoteSeekPreview(at timestamp: TimeInterval? = nil) {
        remoteSeekCoordinator.refreshActiveRemoteSeekPreview(at: timestamp)
    }

    /// Starts or resumes playback cleanly.
    public func play() {
        resetInactivityTimer()
        activeEngine.play()
        playbackState = activeEngine.playbackState
        isPlaying = activeEngine.isPlaying
        publishNowPlaying(force: true)
    }

    /// Pauses playback cleanly.
    public func pause() {
        resetInactivityTimer()
        activeEngine.pause()
        playbackState = activeEngine.playbackState
        isPlaying = activeEngine.isPlaying
        saveCurrentProgressSnapshot()
        publishNowPlaying(force: true)
    }

    /// Handles hardware/Siri Remote Play/Pause presses while deduplicating potential dual MediaRemote delivery.
    public func handlePlayPauseCommand() {
        lastLocalPlayPauseUptime = uptimeProvider()
        togglePlayPause()
    }

    /// Toggles play / pause (always works regardless of overlay state).
    public func togglePlayPause() {
        resetInactivityTimer()
        activeEngine.togglePlayPause()
        playbackState = activeEngine.playbackState
        isPlaying = activeEngine.isPlaying
        if !isPlaying {
            saveCurrentProgressSnapshot()
        }
        publishNowPlaying(force: true)
    }

    /// Selects an audio track on the active playback engine.
    public func selectAudioTrack(_ track: PlayerAudioTrack) {
        resetInactivityTimer()
        activeEngine.selectAudioTrack(track)
        selectedAudioTrack = activeEngine.selectedAudioTrack
    }

    /// Selects a subtitle track (or `nil` to disable subtitles) on the active playback engine.
    public func selectSubtitleTrack(_ track: PlayerSubtitleTrack?) {
        resetInactivityTimer()
        activeEngine.selectSubtitleTrack(track)
        selectedSubtitleTrack = activeEngine.selectedSubtitleTrack
    }

    // MARK: - Scrubbing & Acceleration

    public func adjustScrub(forward: Bool) {
        remoteSeekCoordinator.adjustScrub(forward: forward)
    }

    public func commitScrub() {
        remoteSeekCoordinator.commitScrub()
    }

    public func cancelScrub() {
        remoteSeekCoordinator.cancelScrub()
    }

    // MARK: - Remote Seek Mechanics

    public func commitRemoteSeek(to targetTime: Double, at timestamp: TimeInterval) {
        activeEngine.seek(to: targetTime, precision: .fast)
        currentTime = targetTime
        remoteSeekCoordinator.recordCommittedSeek(target: targetTime, at: timestamp)
        saveCurrentProgressSnapshot()
        publishNowPlaying(force: true)
        resetInactivityTimer()
    }

    private func clearRemoteSeekState() {
        remoteSeekCoordinator.reset()
    }

    // MARK: - Seek Frame Thumbnail Preview Worker

    public func requestSeekThumbnail(for targetTime: Double) {
        let targetURL = directSMBURL ?? resolvedMediaURL
        thumbnailCoordinator.requestSeekThumbnail(
            for: targetTime,
            duration: duration,
            assetKey: currentItem.id,
            targetURL: targetURL,
            engineKind: activeEngineKind,
            vlcOptions: vlcPlaybackOptions,
            activeTargetProvider: { [weak self] in
                self?.remoteSeekCoordinator.resolveActiveThumbnailTarget()
            }
        )
    }

    private func cancelSeekThumbnails(clearState: Bool) {
        thumbnailCoordinator.cancelSeekThumbnails(clearState: clearState)
    }

    private func resetCachedSeekThumbnails() {
        thumbnailCoordinator.reset(forAssetKey: nil)
    }

    private func activateRemoteCommandBridgeIfNeeded() {
        guard !isRemoteCommandBridgeActive else { return }
        isRemoteCommandBridgeActive = true

        let callbacks = TVRemoteCommandCallbacks(
            onSeekBegan: { [weak self] isForward, uptime in
                self?.beginRemoteSeek(isForward: isForward, source: .hardwareMediaCommand, timestamp: uptime)
            },
            onSeekEnded: { [weak self] isForward, uptime in
                self?.endRemoteSeek(isForward: isForward, source: .hardwareMediaCommand, timestamp: uptime)
            },
            onTapSkip: { [weak self] isForward, uptime in
                self?.triggerRemoteTapSkip(isForward: isForward, timestamp: uptime)
            },
            onPlay: { [weak self] in
                self?.play()
            },
            onPause: { [weak self] in
                self?.pause()
            },
            onTogglePlayPause: { [weak self] uptime in
                guard let self else { return }
                if let lastLocal = self.lastLocalPlayPauseUptime, abs(uptime - lastLocal) < 0.08 {
                    return
                }
                self.togglePlayPause()
            }
        )
        remoteCommandBridge.activate(callbacks: callbacks)
    }

    private func deactivateRemoteCommandBridge() {
        guard isRemoteCommandBridgeActive else { return }
        isRemoteCommandBridgeActive = false
        remoteCommandBridge.deactivate()
    }

    private func publishNowPlaying(force: Bool) {
        guard isRemoteCommandBridgeActive else { return }
        if !force && abs(currentTime - lastPublishedNowPlayingTime) < 1.0 {
            return
        }
        lastPublishedNowPlayingTime = currentTime
        remoteCommandBridge.updateNowPlaying(
            title: currentItem.name,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    // MARK: - Button Row Navigation

    private func moveButtonFocus(forward: Bool) {
        switch activeFocusedButton {
        case .previous:
            if forward { activeFocusedButton = .playPause }
        case .playPause:
            activeFocusedButton = forward ? .next : .previous
        case .next:
            activeFocusedButton = forward ? .chapters : .playPause
        case .chapters:
            activeFocusedButton = forward ? .tracks : .next
        case .tracks:
            activeFocusedButton = forward ? .speed : .chapters
        case .speed:
            activeFocusedButton = forward ? (activeEngineKind == .native ? .pip : .switchEngine) : .tracks
        case .pip:
            activeFocusedButton = forward ? .switchEngine : .speed
        case .switchEngine:
            if !forward {
                activeFocusedButton = (activeEngineKind == .native) ? .pip : .speed
            }
        }
    }

    private func activateFocusedButton() {
        switch activeFocusedButton {
        case .previous:
            previousVideo()
        case .playPause:
            togglePlayPause()
        case .next:
            nextVideo()
        case .switchEngine:
            switchEngine()
        case .chapters:
            openChaptersMenu()
        case .tracks:
            openTracksMenu()
        case .speed:
            openSpeedMenu()
        case .pip:
            togglePiP()
        }
    }

    /// Toggles Picture-in-Picture presentation for the native playback engine on tvOS.
    public func togglePiP() {
        resetInactivityTimer()
        guard activeEngineKind == .native else { return }
        pipCoordinator.togglePiP()
    }

    public func nextVideo() {
        if currentIndex < videos.count - 1 {
            saveCurrentProgressSnapshot()
            currentIndex += 1
            loadCurrentVideo()
            scheduleLookaheadIfNeeded()
        } else if hasMoreSourcePages {
            loadMoreAndAdvance()
        }
    }

    public func previousVideo() {
        if currentIndex > 0 {
            saveCurrentProgressSnapshot()
            currentIndex -= 1
            loadCurrentVideo()
        }
    }

    // MARK: - Inactivity Timer & Resume Playback

    public func resetInactivityTimer() {
        autoHideTask?.cancel()
        guard isPlaying, !isScrubbing, !isShowingTracksSheet, !isShowingChaptersSheet, !isShowingSpeedSheet, !isRemoteSeekHolding else { return }

        autoHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            if self.isPlaying && !self.isScrubbing && !self.isShowingTracksSheet && !self.isShowingChaptersSheet && !self.isShowingSpeedSheet && !self.isRemoteSeekHolding {
                withAnimation(.snappy) {
                    self.showOverlay = false
                }
            }
        }
    }

    private func restorePlaybackPosition(for itemID: String, on engine: any PlayerEngine) {
        playbackPositionRestoreTask?.cancel()
        playbackPositionRestoreTask = Task { [weak self] in
            guard let self else { return }
            if let savedTime = await self.playbackStore.playbackPosition(for: itemID),
               !Task.isCancelled,
               self.currentItem.id == itemID {
                engine.seek(to: savedTime)
                self.currentTime = engine.currentTime
            }
        }
    }

    private func startProgressPersistenceLoop() {
        progressPersistenceTask?.cancel()
        progressPersistenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                if self.isPlaying {
                    let itemID = self.currentItem.id
                    let time = self.currentTime
                    let dur = self.duration
                    await self.playbackStore.savePlaybackPosition(itemID: itemID, time: time, duration: dur)
                }
            }
        }
    }

    private func saveCurrentProgressSnapshot() {
        let itemID = currentItem.id
        let time = currentTime
        let dur = duration
        Task { [playbackStore] in
            await playbackStore.savePlaybackPosition(itemID: itemID, time: time, duration: dur)
        }
    }

    // MARK: - Engine Setup & Fallback

    private func setupEngineCallbacks() {
        nativeEngine.onError = { [weak self] error in
            guard let self, self.activeEngineKind == .native else { return }
            self.attemptEngineFallback(from: .native, failedError: error)
        }
        nativeEngine.onPlaybackEnded = { [weak self] in
            guard let self, self.activeEngineKind == .native else { return }
            self.handlePlaybackCompletion()
        }
        nativeEngine.onStateUpdate = { [weak self] state in
            guard let self, self.activeEngineKind == .native else { return }
            self.playbackState = state
            self.isPlaying = self.nativeEngine.isPlaying
            if state == .playing {
                self.resetInactivityTimer()
            }
            self.publishNowPlaying(force: true)
        }
        nativeEngine.onTimeUpdate = { [weak self] time in
            guard let self, self.activeEngineKind == .native else { return }
            self.currentTime = time
            self.publishNowPlaying(force: false)
        }
        nativeEngine.onDurationUpdate = { [weak self] duration in
            guard let self, self.activeEngineKind == .native else { return }
            self.duration = duration
            self.publishNowPlaying(force: true)
        }
        nativeEngine.onTracksChanged = { [weak self] in
            guard let self, self.activeEngineKind == .native else { return }
            self.syncTracks(from: self.nativeEngine)
        }
        nativeEngine.onChaptersChanged = { [weak self] in
            guard let self, self.activeEngineKind == .native else { return }
            self.availableChapters = self.nativeEngine.availableChapters
        }

        extendedEngine.onError = { [weak self] error in
            guard let self, self.activeEngineKind == .extended else { return }
            self.attemptEngineFallback(from: .extended, failedError: error)
        }
        extendedEngine.onPlaybackEnded = { [weak self] in
            guard let self, self.activeEngineKind == .extended else { return }
            self.handlePlaybackCompletion()
        }
        extendedEngine.onStateUpdate = { [weak self] state in
            guard let self, self.activeEngineKind == .extended else { return }
            self.playbackState = state
            self.isPlaying = self.extendedEngine.isPlaying
            if state == .playing {
                self.resetInactivityTimer()
            }
            self.publishNowPlaying(force: true)
        }
        extendedEngine.onTimeUpdate = { [weak self] time in
            guard let self, self.activeEngineKind == .extended else { return }
            self.currentTime = time
            self.publishNowPlaying(force: false)
        }
        extendedEngine.onDurationUpdate = { [weak self] duration in
            guard let self, self.activeEngineKind == .extended else { return }
            self.duration = duration
            self.publishNowPlaying(force: true)
        }
        extendedEngine.onTracksChanged = { [weak self] in
            guard let self, self.activeEngineKind == .extended else { return }
            self.syncTracks(from: self.extendedEngine)
        }
        extendedEngine.onChaptersChanged = { [weak self] in
            guard let self, self.activeEngineKind == .extended else { return }
            self.availableChapters = self.extendedEngine.availableChapters
        }
    }

    private func handlePlaybackCompletion() {
        let finishedID = currentItem.id
        Task { [playbackStore] in
            await playbackStore.clearPlaybackPosition(for: finishedID)
        }
        if currentIndex < videos.count - 1 {
            currentIndex += 1
            loadCurrentVideo()
            scheduleLookaheadIfNeeded()
        } else if hasMoreSourcePages {
            loadMoreAndAdvance()
        }
    }

    private func attemptEngineFallback(from failedKind: PlayerEngineKind, failedError: Error) {
        guard !hasAttemptedFallback, let url = resolvedMediaURL else {
            playbackState = .failed(failedError.localizedDescription)
            errorMessage = failedError.localizedDescription
            return
        }
        hasAttemptedFallback = true

        // Section 9: Try the other engine (AVPlayer <-> TVVLCPlayerEngine) before surfacing an error
        let fallbackKind: PlayerEngineKind = (failedKind == .native) ? .extended : .native
        activeEngine.tearDown()

        if fallbackKind == .extended {
            smbResourceLoaderDelegate?.cancelAll()
            smbResourceLoaderDelegate = nil
            if let directSMBURL {
                resolvedMediaURL = directSMBURL
                mount(url: directSMBURL, kind: .extended)
                return
            } else if currentItem.sourceID != nil, currentItem.smbShare != nil, currentItem.smbPath != nil {
                loadSMBVideo(item: currentItem, preferredKind: .extended)
                return
            }
        } else if fallbackKind == .native {
            if directSMBURL != nil || (currentItem.sourceID != nil && currentItem.smbShare != nil && currentItem.smbPath != nil) {
                loadSMBVideo(item: currentItem, preferredKind: .native)
                return
            }
        }

        mount(url: url, kind: fallbackKind)
    }

    private func mount(url: URL, kind: PlayerEngineKind, playerItem: AVPlayerItem? = nil) {
        if kind == .extended {
            pipCoordinator.reset()
            isPiPActive = false
            nativeEngine.pause()
        } else {
            extendedEngine.pause()
        }
        setActiveEngine(kind: kind)

        switch kind {
        case .native:
            if let playerItem {
                nativeEngine.load(playerItem: playerItem)
            } else {
                nativeEngine.load(url: url)
            }
            nativeEngine.playbackRate = playbackRate.rawValue
            nativeEngine.play()
        case .extended:
            extendedEngine.load(url: url, startPosition: 0, options: vlcPlaybackOptions)
            extendedEngine.playbackRate = playbackRate.rawValue
            extendedEngine.play()
        }

        syncState(from: activeEngine)
        restorePlaybackPosition(for: currentItem.id, on: activeEngine)
        startProgressPersistenceLoop()
        resetInactivityTimer()
        publishNowPlaying(force: true)
    }

    private func setActiveEngine(kind: PlayerEngineKind) {
        activeEngineKind = kind
        switch kind {
        case .native:
            activeEngine = nativeEngine
        case .extended:
            activeEngine = extendedEngine
            if activeFocusedButton == .pip {
                activeFocusedButton = .playPause
            }
        }
        syncState(from: activeEngine)
    }

    private func syncState(from engine: any PlayerEngine) {
        playbackState = engine.playbackState
        currentTime = engine.currentTime
        duration = engine.duration
        isPlaying = engine.isPlaying
        availableChapters = engine.availableChapters
        syncTracks(from: engine)
    }

    private func syncTracks(from engine: any PlayerEngine) {
        availableAudioTracks = engine.availableAudioTracks
        selectedAudioTrack = engine.selectedAudioTrack
        availableSubtitleTracks = engine.availableSubtitleTracks
        selectedSubtitleTrack = engine.selectedSubtitleTrack
    }

    private func loadPhotoKitVideo(assetIdentifier: String, itemID: String, preferredKind: PlayerEngineKind) {
        playbackState = .loading
        mediaLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await PhotoVideoLoader.shared.loadVideoURL(for: assetIdentifier)
                guard !Task.isCancelled, self.currentItem.id == itemID else { return }
                self.resolvedMediaURL = url
                self.mount(url: url, kind: preferredKind)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.currentItem.id == itemID else { return }
                self.playbackState = .failed(error.localizedDescription)
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func loadSMBVideo(item: MediaSourceItem, preferredKind: PlayerEngineKind) {
        guard let sourceID = item.sourceID,
              let share = item.smbShare,
              let path = item.smbPath else { return }

        let fileName = item.name
        let totalSize = item.size
        let itemID = item.id

        playbackState = .loading
        mediaLoadTask = Task { [weak self] in
            guard let self, !Task.isCancelled, self.currentItem.id == itemID else { return }

            guard let sharesSource = await self.resolver.resolve(sourceID: sourceID) as? SharesMediaSource else {
                guard !Task.isCancelled, self.currentItem.id == itemID else { return }
                let errorDesc = String(localized: .Strings.videoPlayerErrorResolveServer)
                self.playbackState = .failed(errorDesc)
                self.errorMessage = errorDesc
                return
            }

            guard let resolvedSMBURL = VLCPlaybackOptions.makeSMBURL(
                host: sharesSource.server.host,
                share: share,
                relativePath: path
            ) else {
                guard !Task.isCancelled, self.currentItem.id == itemID else { return }
                let errorDesc = String(localized: .Strings.videoPlayerErrorDirectSmbUrl)
                self.playbackState = .failed(errorDesc)
                self.errorMessage = errorDesc
                return
            }

            self.directSMBURL = resolvedSMBURL
            self.vlcPlaybackOptions = VLCPlaybackOptions(
                username: sharesSource.server.username,
                password: sharesSource.password
            )

            guard !Task.isCancelled, self.currentItem.id == itemID else { return }

            if preferredKind == .native && totalSize > 0 {
                self.smbResourceLoaderDelegate?.cancelAll()

                let streamURL = SMBAVAssetResourceLoaderDelegate.makeStreamURL(fileName: fileName)
                let delegate = SMBAVAssetResourceLoaderDelegate(
                    client: sharesSource.client,
                    share: share,
                    path: path,
                    fileName: fileName,
                    fileSize: totalSize,
                    chunkSize: 512 * 1024
                )
                self.smbResourceLoaderDelegate = delegate

                let asset = AVURLAsset(url: streamURL)
                asset.resourceLoader.setDelegate(delegate, queue: FichierResourceLoaderQueue.shared)
                self.thumbnailCoordinator.registerAsset(asset, forAssetKey: itemID)

                let playerItem = AVPlayerItem(asset: asset)
                playerItem.preferredForwardBufferDuration = 2.0
                self.resolvedMediaURL = streamURL
                self.mount(url: streamURL, kind: .native, playerItem: playerItem)
            } else {
                self.resolvedMediaURL = resolvedSMBURL
                self.mount(url: resolvedSMBURL, kind: .extended)
            }
        }
    }

    func setResolvedMediaURLForTesting(_ url: URL) {
        resolvedMediaURL = url
    }

    // MARK: - Multi-Page Source Lookahead & Video Pagination

    private func scheduleLookaheadIfNeeded() {
        let bufferedAhead = (videos.count - 1) - currentIndex
        guard hasMoreSourcePages, bufferedAhead <= 5, paginationTask == nil else { return }
        paginationTask = Task { [weak self] in
            guard let self else { return }
            await self.performFetchLookaheadVideos(targetBufferCount: 6)
        }
    }

    private func loadMoreAndAdvance() {
        guard paginationTask == nil else { return }
        paginationTask = Task { [weak self] in
            guard let self else { return }
            await self.performFetchLookaheadVideos(targetBufferCount: 1, advanceWhenReady: true)
        }
    }

    private func performFetchLookaheadVideos(targetBufferCount: Int, advanceWhenReady: Bool = false) async {
        defer { paginationTask = nil }
        guard hasMoreSourcePages, let context = paginationContext else { return }

        if paginationSource == nil {
            paginationSource = await resolver.resolve(sourceID: context.sourceID)
        }
        guard !Task.isCancelled, let source = paginationSource else {
            hasMoreSourcePages = false
            return
        }

        while !Task.isCancelled && hasMoreSourcePages {
            let bufferedAhead = (videos.count - 1) - currentIndex
            if !advanceWhenReady && bufferedAhead >= targetBufferCount {
                break
            }

            let page = nextPageToFetch
            do {
                let fetched = try await source.fetchItems(
                    in: context.folder,
                    sortBy: context.sortKey,
                    order: context.sortOrder,
                    page: page,
                    pageSize: context.pageSize
                )
                guard !Task.isCancelled else { break }

                nextPageToFetch = page + 1
                if fetched.count < context.pageSize {
                    hasMoreSourcePages = false
                }

                let newVideos = fetched.filter { $0.type == .video && seenItemIDs.insert($0.id).inserted }

                if !newVideos.isEmpty {
                    videos.append(contentsOf: newVideos)
                    if advanceWhenReady && currentIndex < videos.count - 1 {
                        saveCurrentProgressSnapshot()
                        currentIndex += 1
                        loadCurrentVideo()
                        break
                    }
                }
            } catch {
                Self.logger.error("Failed to paginate video source: \(error.localizedDescription)")
                hasMoreSourcePages = false
                break
            }
        }
    }

    /// Clears the disappearance flag when the player view appears or restores from PiP.
    public func handleViewAppear() {
        hasDisappeared = false
    }

    /// Defers teardown while PiP is active and tears down immediately otherwise.
    public func handleViewDisappear() {
        hasDisappeared = true
        guard !isPiPActive else { return }
        tearDown()
    }

    public func tearDown() {
        hasDisappeared = false
        saveCurrentProgressSnapshot()
        clearRemoteSeekState()
        resetCachedSeekThumbnails()
        availableChapters = []
        directSMBURL = nil
        vlcPlaybackOptions = nil
        smbResourceLoaderDelegate?.cancelAll()
        smbResourceLoaderDelegate = nil
        deactivateRemoteCommandBridge()
        mediaLoadTask?.cancel()
        mediaLoadTask = nil
        playbackPositionRestoreTask?.cancel()
        playbackPositionRestoreTask = nil
        thumbnailCoordinator.cancelSeekThumbnails(clearState: true)
        autoHideTask?.cancel()
        autoHideTask = nil
        progressPersistenceTask?.cancel()
        progressPersistenceTask = nil
        paginationTask?.cancel()
        paginationTask = nil
        pipCoordinator.reset()
        nativeEngine.tearDown()
        extendedEngine.tearDown()
        isPiPActive = false
        syncState(from: activeEngine)
    }
}
