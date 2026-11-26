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
    static let logger = Logger(subsystem: "com.acme.ios.fichiertv", category: "videoPlayerViewModel")

    public internal(set) var videos: [MediaSourceItem]
    public internal(set) var currentIndex: Int
    let paginationContext: TVViewerPaginationContext?
    var paginationSource: (any MediaSource)?
    var nextPageToFetch: Int
    var hasMoreSourcePages: Bool
    var seenItemIDs: Set<String>
    var paginationTask: Task<Void, Never>?

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

    public internal(set) var playbackState: PlayerPlaybackState = .idle
    public internal(set) var currentTime: Double = 0
    public private(set) var duration: Double = 0
    public internal(set) var isPlaying: Bool = false
    public private(set) var availableAudioTracks: [PlayerAudioTrack] = []
    public internal(set) var selectedAudioTrack: PlayerAudioTrack?
    public private(set) var availableSubtitleTracks: [PlayerSubtitleTrack] = []
    public internal(set) var selectedSubtitleTrack: PlayerSubtitleTrack?
    public private(set) var availableChapters: [PlayerChapter] = []
    public internal(set) var playbackRate: TVVideoPlaybackRate = .normal
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

    let playbackStore: any VideoPlaybackStoreProtocol
    let resolver: any MediaSourceResolverProtocol
    let remoteCommandBridge: any TVRemoteCommandHandling
    private let thumbnailProvider: any TVSeekThumbnailProviding
    let uptimeProvider: @MainActor @Sendable () -> TimeInterval
    var autoHideTask: Task<Void, Never>?
    var progressPersistenceTask: Task<Void, Never>?
    private var mediaLoadTask: Task<Void, Never>?
    var playbackPositionRestoreTask: Task<Void, Never>?
    var resolvedMediaURL: URL?
    var directSMBURL: URL?
    var vlcPlaybackOptions: VLCPlaybackOptions?
    private var smbResourceLoaderDelegate: SMBAVAssetResourceLoaderDelegate?
    private var hasAttemptedFallback: Bool = false
    var isRemoteCommandBridgeActive: Bool = false
    var lastLocalPlayPauseUptime: TimeInterval?
    var lastPublishedNowPlayingTime: Double = -10

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
