//
//  TVVideoPlayerViewModel.swift
//  FichierTV
//
//

import SwiftUI
import Observation
import AVFoundation
import FichierKit

/// Master state coordinator for the tvOS video player, handling dual playback engines (`AVPlayerEngine` and `TVVLCPlayerEngine`),
/// PhotoKit and SMB video resolution, Siri Remote scrubbing acceleration, multi-tiered Menu back handling, resume-playback, and auto-hide.
@Observable
@MainActor
public final class TVVideoPlayerViewModel {
    // swiftlint:disable:next no_legacy_dispatch_queue
    private static let smbResourceLoaderQueue = DispatchQueue(
        label: "com.acme.ios.fichier.tv.videoloader",
        qos: .userInitiated
    )

    public let videos: [MediaSourceItem]
    public private(set) var currentIndex: Int

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

    public var showOverlay: Bool = false
    public var activeFocusRow: TVVideoPlayerFocusRow = .buttons
    public var activeFocusedButton: TVVideoPlayerButtonKind = .playPause
    public var isScrubbing: Bool = false
    public var scrubbingTime: Double?

    public private(set) var errorMessage: String?
    public var isShowingChaptersSheet: Bool = false
    public var isShowingTracksSheet: Bool = false
    public var isShowingSpeedSheet: Bool = false
    public private(set) var remoteSeekPreview: TVRemoteSeekPreview?
    public private(set) var seekThumbnailState: TVSeekThumbnailState?

    public var isRemoteSeekHolding: Bool {
        activeRemoteSeekHold?.wasCancelledByMenu == false
    }

    private let playbackStore: any VideoPlaybackStoreProtocol
    private let resolver: any MediaSourceResolverProtocol
    private let remoteCommandBridge: any TVRemoteCommandHandling
    private let thumbnailProvider: any TVSeekThumbnailProviding
    private let uptimeProvider: @MainActor @Sendable () -> TimeInterval
    private var autoHideTask: Task<Void, Never>?
    private var progressPersistenceTask: Task<Void, Never>?
    private var mediaLoadTask: Task<Void, Never>?
    private var remoteSeekHoldTask: Task<Void, Never>?
    private var remoteSeekPreviewDismissTask: Task<Void, Never>?
    private var thumbnailWorkerTask: Task<Void, Never>?
    private var resolvedMediaURL: URL?
    private var directSMBURL: URL?
    private var vlcPlaybackOptions: VLCPlaybackOptions?
    private var smbResourceLoaderDelegate: SMBAVAssetResourceLoaderDelegate?
    private var scrubHoldCounter: Int = 0
    private var hasAttemptedFallback: Bool = false
    private var isRemoteCommandBridgeActive: Bool = false
    private var activeRemoteSeekHold: TVRemoteSeekHoldState?
    private var lastRemoteSeekTap: TVRemoteSeekTapState?
    private var recentCommittedSeekTarget: Double?
    private var recentCommittedSeekUptime: TimeInterval?
    private var lastLocalPlayPauseUptime: TimeInterval?
    private var lastPublishedNowPlayingTime: Double = -10
    private var latestThumbnailRequest: TVSeekThumbnailRequest?
    private var latestThumbnailBucket: Double?
    private var cachedBucketImages: [Int: UIImage] = [:]
    private var cachedBucketOrder: [Int] = []

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
        }
    }

    public init(
        initialItem: MediaSourceItem,
        videos: [MediaSourceItem],
        playbackStore: any VideoPlaybackStoreProtocol = DefaultVideoPlaybackStore.shared,
        resolver: any MediaSourceResolverProtocol = DefaultMediaSourceResolver.shared,
        remoteCommandBridge: any TVRemoteCommandHandling = TVSystemRemoteCommandBridge(),
        thumbnailProvider: any TVSeekThumbnailProviding = TVSeekThumbnailService(),
        uptimeProvider: @escaping @MainActor @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        let filteredVideos = videos.filter { $0.type == .video }
        self.videos = filteredVideos.isEmpty ? [initialItem] : filteredVideos
        self.currentIndex = self.videos.firstIndex(where: { $0.id == initialItem.id }) ?? 0

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
        isScrubbing = false
        scrubbingTime = nil
        scrubHoldCounter = 0
        clearRemoteSeekState()
        resetCachedSeekThumbnails()
        lastPublishedNowPlayingTime = -10
        activateRemoteCommandBridgeIfNeeded()

        mediaLoadTask?.cancel()
        mediaLoadTask = nil
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

        if let localURL = item.localURL {
            resolvedMediaURL = localURL
            mount(url: localURL, kind: initialKind)
        } else if let phID = item.phAssetIdentifier {
            loadPhotoKitVideo(assetIdentifier: phID, itemID: item.id, preferredKind: initialKind)
        } else if let sourceID = item.sourceID,
                  let share = item.smbShare,
                  let smbPath = item.smbPath {
            loadSMBVideo(
                sourceID: sourceID,
                share: share,
                path: smbPath,
                fileName: item.name,
                totalSize: item.size,
                itemID: item.id,
                preferredKind: initialKind
            )
        } else {
            playbackState = .failed("Unable to locate video source for \(item.name).")
            errorMessage = "Unable to locate video source for \(item.name)."
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
        scrubHoldCounter = 0
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

        cancelScrub()
        activeRemoteSeekHold = nil
        remoteSeekHoldTask?.cancel()
        remoteSeekHoldTask = nil
        cancelSeekThumbnails(clearState: true)

        commitRemoteSeek(to: clamped, at: uptimeProvider())
        presentRemoteSeekPreview(
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

        if let hold = activeRemoteSeekHold, !hold.wasCancelledByMenu {
            activeRemoteSeekHold = hold.cancellingByMenu()
            remoteSeekHoldTask?.cancel()
            remoteSeekHoldTask = nil
            remoteSeekPreviewDismissTask?.cancel()
            remoteSeekPreviewDismissTask = nil
            remoteSeekPreview = nil
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

        let eventTime = timestamp ?? uptimeProvider()
        if let existing = activeRemoteSeekHold,
           !existing.wasCancelledByMenu,
           existing.source == source,
           existing.isForward == isForward {
            return
        }

        if isScrubbing {
            cancelScrub()
        }

        autoHideTask?.cancel()
        remoteSeekHoldTask?.cancel()
        remoteSeekHoldTask = nil
        remoteSeekPreviewDismissTask?.cancel()
        remoteSeekPreviewDismissTask = nil

        let anchorTime = effectiveSeekBaseTime(at: eventTime)
        activeRemoteSeekHold = TVRemoteSeekHoldState(
            isForward: isForward,
            source: source,
            anchorTime: anchorTime,
            startTimestamp: eventTime,
            wasCancelledByMenu: false
        )
        startRemoteSeekHoldPreviewLoop()
    }

    /// Completes a `<<` / `>>` press gesture as a tap (`±15s`), double-tap within `0.50s` (`±60s`),
    /// or progressive hold multiplier seek (`>= 0.30s`).
    public func endRemoteSeek(
        isForward: Bool,
        source: TVRemoteSeekSource,
        timestamp: TimeInterval? = nil
    ) {
        let releaseTime = timestamp ?? uptimeProvider()

        guard let hold = activeRemoteSeekHold,
              hold.source == source,
              hold.isForward == isForward else {
            if source == .hardwareMediaCommand {
                triggerRemoteTapSkip(isForward: isForward, timestamp: releaseTime)
            }
            return
        }

        activeRemoteSeekHold = nil
        remoteSeekHoldTask?.cancel()
        remoteSeekHoldTask = nil

        guard !hold.wasCancelledByMenu else {
            remoteSeekPreview = nil
            resetInactivityTimer()
            return
        }

        let heldDuration = max(0, releaseTime - hold.startTimestamp)
        if heldDuration < TVRemoteSeekCalculator.shortTapMaxDuration {
            performRemoteTapSkip(
                isForward: isForward,
                baseAnchorTime: hold.anchorTime,
                timestamp: releaseTime
            )
            return
        }

        lastRemoteSeekTap = nil
        let magnitude = TVRemoteSeekCalculator.progressiveHoldMagnitude(
            for: heldDuration,
            totalDuration: duration
        )
        let signedDelta = isForward ? magnitude : -magnitude
        let targetTime = TVRemoteSeekCalculator.clampedTarget(
            from: hold.anchorTime,
            signedDelta: signedDelta,
            duration: duration
        )
        let appliedDelta = targetTime - hold.anchorTime

        cancelSeekThumbnails(clearState: false)
        if seekThumbnailState?.image == nil {
            seekThumbnailState = nil
        }

        commitRemoteSeek(to: targetTime, at: releaseTime)
        presentRemoteSeekPreview(
            TVRemoteSeekPreview(targetTime: targetTime, deltaSeconds: appliedDelta, isHolding: false)
        )
    }

    /// Cancels an active press gesture without seeking playback (for example when UIKit cancels a press).
    public func cancelRemoteSeek(isForward: Bool, source: TVRemoteSeekSource) {
        guard let hold = activeRemoteSeekHold,
              hold.source == source,
              hold.isForward == isForward else {
            return
        }
        activeRemoteSeekHold = nil
        remoteSeekHoldTask?.cancel()
        remoteSeekHoldTask = nil
        remoteSeekPreviewDismissTask?.cancel()
        remoteSeekPreviewDismissTask = nil
        remoteSeekPreview = nil
        cancelSeekThumbnails(clearState: true)
        resetInactivityTimer()
    }

    /// Executes an immediate discrete `±15s` tap (upgrading to `±60s` total on a second tap within `0.50s`).
    public func triggerRemoteTapSkip(isForward: Bool, timestamp: TimeInterval? = nil) {
        guard errorMessage == nil, !videos.isEmpty else { return }

        let eventTime = timestamp ?? uptimeProvider()
        if isScrubbing {
            cancelScrub()
        }
        activeRemoteSeekHold = nil
        remoteSeekHoldTask?.cancel()
        remoteSeekHoldTask = nil

        let baseAnchorTime = effectiveSeekBaseTime(at: eventTime)
        performRemoteTapSkip(
            isForward: isForward,
            baseAnchorTime: baseAnchorTime,
            timestamp: eventTime
        )
    }

    /// Updates live preview state when an active hold has crossed the hold threshold (exposed for tests and 20 Hz loop).
    public func refreshActiveRemoteSeekPreview(at timestamp: TimeInterval? = nil) {
        guard let hold = activeRemoteSeekHold, !hold.wasCancelledByMenu else { return }
        let now = timestamp ?? uptimeProvider()
        let elapsed = max(0, now - hold.startTimestamp)
        guard elapsed >= TVRemoteSeekCalculator.shortTapMaxDuration else { return }

        let magnitude = TVRemoteSeekCalculator.progressiveHoldMagnitude(
            for: elapsed,
            totalDuration: duration
        )
        let signedDelta = hold.isForward ? magnitude : -magnitude
        let targetTime = TVRemoteSeekCalculator.clampedTarget(
            from: hold.anchorTime,
            signedDelta: signedDelta,
            duration: duration
        )
        let appliedDelta = targetTime - hold.anchorTime
        remoteSeekPreview = TVRemoteSeekPreview(
            targetTime: targetTime,
            deltaSeconds: appliedDelta,
            isHolding: true
        )
        requestSeekThumbnail(for: targetTime)
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

    private func adjustScrub(forward: Bool) {
        isScrubbing = true
        scrubHoldCounter += 1

        let step = TVRemoteSeekCalculator.scrubStepMagnitude(
            consecutiveSteps: scrubHoldCounter,
            totalDuration: duration
        )
        let baseTime = scrubbingTime ?? currentTime
        let target = forward ? baseTime + step : baseTime - step
        let upperBound = duration > 0 ? duration : max(baseTime + step, target)
        let clamped = max(0, min(upperBound, target))
        scrubbingTime = clamped
        requestSeekThumbnail(for: clamped)
    }

    private func commitScrub() {
        if let target = scrubbingTime {
            activeEngine.seek(to: target, precision: .fast)
            currentTime = target
            recordCommittedSeek(target: target, at: uptimeProvider())
            saveCurrentProgressSnapshot()
            publishNowPlaying(force: true)
        }
        isScrubbing = false
        scrubbingTime = nil
        scrubHoldCounter = 0
        cancelSeekThumbnails(clearState: true)
    }

    private func cancelScrub() {
        isScrubbing = false
        scrubbingTime = nil
        scrubHoldCounter = 0
        cancelSeekThumbnails(clearState: true)
    }

    // MARK: - Remote Seek Mechanics

    private func performRemoteTapSkip(
        isForward: Bool,
        baseAnchorTime: Double,
        timestamp: TimeInterval
    ) {
        let sign: Double = isForward ? 1.0 : -1.0

        if let previousTap = lastRemoteSeekTap,
            previousTap.isForward == isForward,
            previousTap.tapCountInPair == 1,
            (timestamp - previousTap.releaseTimestamp) <= TVRemoteSeekCalculator.doubleTapWindow {
            let totalTarget = TVRemoteSeekCalculator.clampedTarget(
                from: previousTap.originTime,
                signedDelta: sign * TVRemoteSeekCalculator.doubleTapTotalSkipSeconds,
                duration: duration
            )
            let appliedDelta = totalTarget - previousTap.originTime
            lastRemoteSeekTap = TVRemoteSeekTapState(
                isForward: isForward,
                releaseTimestamp: timestamp,
                originTime: previousTap.originTime,
                committedTargetTime: totalTarget,
                tapCountInPair: 2
            )
            commitRemoteSeek(to: totalTarget, at: timestamp)
            presentRemoteSeekPreview(
                TVRemoteSeekPreview(targetTime: totalTarget, deltaSeconds: appliedDelta, isHolding: false)
            )
            requestSeekThumbnail(for: totalTarget)
            return
        }

        let targetTime = TVRemoteSeekCalculator.clampedTarget(
            from: baseAnchorTime,
            signedDelta: sign * TVRemoteSeekCalculator.singleTapSkipSeconds,
            duration: duration
        )
        let appliedDelta = targetTime - baseAnchorTime
        lastRemoteSeekTap = TVRemoteSeekTapState(
            isForward: isForward,
            releaseTimestamp: timestamp,
            originTime: baseAnchorTime,
            committedTargetTime: targetTime,
            tapCountInPair: 1
        )
        commitRemoteSeek(to: targetTime, at: timestamp)
        presentRemoteSeekPreview(
            TVRemoteSeekPreview(targetTime: targetTime, deltaSeconds: appliedDelta, isHolding: false)
        )
        requestSeekThumbnail(for: targetTime)
    }

    private func commitRemoteSeek(to targetTime: Double, at timestamp: TimeInterval) {
        activeEngine.seek(to: targetTime, precision: .fast)
        currentTime = targetTime
        recordCommittedSeek(target: targetTime, at: timestamp)
        saveCurrentProgressSnapshot()
        publishNowPlaying(force: true)
        resetInactivityTimer()
    }

    private func effectiveSeekBaseTime(at timestamp: TimeInterval) -> Double {
        if let recentTarget = recentCommittedSeekTarget,
           let recentUptime = recentCommittedSeekUptime,
           (timestamp - recentUptime) <= 1.25,
           abs(currentTime - recentTarget) > 1.5 {
            return recentTarget
        }
        return currentTime
    }

    private func recordCommittedSeek(target: Double, at timestamp: TimeInterval) {
        recentCommittedSeekTarget = target
        recentCommittedSeekUptime = timestamp
    }

    private func startRemoteSeekHoldPreviewLoop() {
        remoteSeekHoldTask?.cancel()
        // Remote hold-to-seek preview. The initial 300 ms delay distinguishes a deliberate hold from a
        // short tap (taps are handled as a fixed jump). The loop then refreshes the preview target at
        // a fixed tick, growing the step with hold duration, until the press ends or Menu cancels it.
        // `self` is re-bound on each iteration so the task never keeps the view model alive.
        remoteSeekHoldTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            while !Task.isCancelled {
                guard let self, let hold = self.activeRemoteSeekHold, !hold.wasCancelledByMenu else {
                    return
                }
                let elapsed = self.uptimeProvider() - hold.startTimestamp
                let effectiveElapsed = max(TVRemoteSeekCalculator.shortTapMaxDuration, elapsed)
                let magnitude = TVRemoteSeekCalculator.progressiveHoldMagnitude(
                    for: effectiveElapsed,
                    totalDuration: self.duration
                )
                let signedDelta = hold.isForward ? magnitude : -magnitude
                let targetTime = TVRemoteSeekCalculator.clampedTarget(
                    from: hold.anchorTime,
                    signedDelta: signedDelta,
                    duration: self.duration
                )
                let appliedDelta = targetTime - hold.anchorTime
                self.remoteSeekPreview = TVRemoteSeekPreview(
                    targetTime: targetTime,
                    deltaSeconds: appliedDelta,
                    isHolding: true
                )
                self.requestSeekThumbnail(for: targetTime)
                try? await Task.sleep(nanoseconds: TVRemoteSeekCalculator.holdTickIntervalNanoseconds)
            }
        }
    }

    private func presentRemoteSeekPreview(_ preview: TVRemoteSeekPreview) {
        remoteSeekPreviewDismissTask?.cancel()
        remoteSeekPreview = preview
        remoteSeekPreviewDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: TVRemoteSeekCalculator.previewVisibleDurationNanoseconds)
            guard !Task.isCancelled, let self else { return }
            if self.activeRemoteSeekHold == nil {
                self.remoteSeekPreview = nil
                if !self.isScrubbing {
                    self.seekThumbnailState = nil
                }
            }
        }
    }

    private func clearRemoteSeekState() {
        remoteSeekHoldTask?.cancel()
        remoteSeekHoldTask = nil
        remoteSeekPreviewDismissTask?.cancel()
        remoteSeekPreviewDismissTask = nil
        activeRemoteSeekHold = nil
        lastRemoteSeekTap = nil
        recentCommittedSeekTarget = nil
        recentCommittedSeekUptime = nil
        remoteSeekPreview = nil
        cancelSeekThumbnails(clearState: true)
    }

    // MARK: - Seek Frame Thumbnail Preview Worker

    private func requestSeekThumbnail(for targetTime: Double) {
        guard let mediaURL = resolvedMediaURL else { return }

        let targetURL = directSMBURL ?? mediaURL
        let safeDuration = duration
        let bucket = TVSeekThumbnailService.bucketTimestamp(targetTime: targetTime, duration: safeDuration)
        let bucketKey = Int(bucket.rounded())
        let request = TVSeekThumbnailRequest(
            url: targetURL,
            assetKey: currentItem.id,
            targetTime: targetTime,
            duration: safeDuration,
            engineKind: activeEngineKind,
            vlcOptions: vlcPlaybackOptions
        )

        latestThumbnailRequest = request
        latestThumbnailBucket = bucket

        if let cachedImage = cachedBucketImages[bucketKey] {
            seekThumbnailState = TVSeekThumbnailState(
                targetTime: targetTime,
                bucketTime: bucket,
                image: cachedImage,
                isLoading: false
            )
            return
        }

        seekThumbnailState = TVSeekThumbnailState(
            targetTime: targetTime,
            bucketTime: bucket,
            image: seekThumbnailState?.image,
            isLoading: true
        )

        if thumbnailWorkerTask == nil {
            thumbnailWorkerTask = Task { [weak self] in
                await self?.runThumbnailWorkerLoop()
            }
        }
    }

    /// Single-flight worker generating seek-preview thumbnails.
    ///
    /// Scrubbing can request dozens of thumbnails per second, so requests are coalesced: only the
    /// newest `latestThumbnailRequest` is processed and older ones are dropped. Times are bucketed
    /// (`bucketTimestamp`) so nearby positions share one cached frame. Short settle and cooldown
    /// delays throttle decoding, which is more expensive for extended (VLC) streams over SMB.
    private func runThumbnailWorkerLoop() async {
        let settleNs: UInt64 = activeEngineKind == .extended ? 140_000_000 : 75_000_000
        try? await Task.sleep(nanoseconds: settleNs)

        while !Task.isCancelled {
            guard let request = latestThumbnailRequest else {
                break
            }
            let targetBucket = TVSeekThumbnailService.bucketTimestamp(
                targetTime: request.targetTime,
                duration: request.duration
            )
            let bucketKey = Int(targetBucket.rounded())
            latestThumbnailRequest = nil

            if let cachedImage = cachedBucketImages[bucketKey] {
                if !Task.isCancelled, resolveActiveThumbnailTarget() != nil,
                   latestThumbnailBucket == targetBucket {
                    seekThumbnailState = TVSeekThumbnailState(
                        targetTime: resolveActiveThumbnailTarget() ?? request.targetTime,
                        bucketTime: targetBucket,
                        image: cachedImage,
                        isLoading: false
                    )
                }
                continue
            }

            let decoded = await thumbnailProvider.generateThumbnail(for: request)
            // Discard the result if the task was cancelled or the player moved to another media item
            // while decoding, so a stale frame from the previous video never shows up.
            let activeTargetURL = directSMBURL ?? resolvedMediaURL
            guard !Task.isCancelled, activeTargetURL == request.url else {
                break
            }

            if let decoded {
                storeCachedBucketImage(decoded, forBucketKey: bucketKey)
            }

            if let activeTarget = resolveActiveThumbnailTarget() {
                let activeBucket = TVSeekThumbnailService.bucketTimestamp(targetTime: activeTarget, duration: duration)
                if activeBucket == targetBucket {
                    seekThumbnailState = TVSeekThumbnailState(
                        targetTime: activeTarget,
                        bucketTime: targetBucket,
                        image: decoded,
                        isLoading: false
                    )
                } else if let decoded {
                    // The user moved on while this frame decoded: show it as a placeholder
                    // (still `isLoading`) until the frame for the new bucket is ready.
                    seekThumbnailState = TVSeekThumbnailState(
                        targetTime: activeTarget,
                        bucketTime: activeBucket,
                        image: decoded,
                        isLoading: true
                    )
                }
            }

            if latestThumbnailRequest != nil {
                let cooldownNs: UInt64
                if request.engineKind == .extended && !request.url.isFileURL {
                    cooldownNs = 300_000_000
                } else {
                    cooldownNs = 60_000_000
                }
                try? await Task.sleep(nanoseconds: cooldownNs)
            }
        }

        thumbnailWorkerTask = nil
    }

    private func resolveActiveThumbnailTarget() -> Double? {
        if isScrubbing, let scrubbingTime {
            return scrubbingTime
        }
        if let preview = remoteSeekPreview {
            return preview.targetTime
        }
        return nil
    }

    private func storeCachedBucketImage(_ image: UIImage, forBucketKey key: Int) {
        if cachedBucketImages[key] == nil {
            cachedBucketOrder.append(key)
            if cachedBucketOrder.count > 48, let evicted = cachedBucketOrder.first {
                cachedBucketOrder.removeFirst()
                cachedBucketImages.removeValue(forKey: evicted)
            }
        }
        cachedBucketImages[key] = image
    }

    private func cancelSeekThumbnails(clearState: Bool) {
        thumbnailWorkerTask?.cancel()
        thumbnailWorkerTask = nil
        latestThumbnailRequest = nil
        latestThumbnailBucket = nil
        if clearState {
            seekThumbnailState = nil
        } else if let currentState = seekThumbnailState {
            seekThumbnailState = TVSeekThumbnailState(
                targetTime: currentState.targetTime,
                bucketTime: currentState.bucketTime,
                image: currentState.image,
                isLoading: false
            )
        }
    }

    private func resetCachedSeekThumbnails() {
        cancelSeekThumbnails(clearState: true)
        cachedBucketImages.removeAll()
        cachedBucketOrder.removeAll()
        let keyToInvalidate = currentItem.id
        Task { [thumbnailProvider] in
            await thumbnailProvider.invalidateAsset(forAssetKey: keyToInvalidate)
        }
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
            activeFocusedButton = forward ? .switchEngine : .tracks
        case .switchEngine:
            if !forward { activeFocusedButton = .speed }
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
            isShowingTracksSheet = true
        case .speed:
            openSpeedMenu()
        }
    }

    public func nextVideo() {
        if currentIndex < videos.count - 1 {
            saveCurrentProgressSnapshot()
            currentIndex += 1
            loadCurrentVideo()
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
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            guard !Task.isCancelled, let self else { return }
            if self.isPlaying && !self.isScrubbing && !self.isShowingTracksSheet && !self.isShowingChaptersSheet && !self.isShowingSpeedSheet && !self.isRemoteSeekHolding {
                withAnimation(.snappy) {
                    self.showOverlay = false
                }
            }
        }
    }

    private func restorePlaybackPosition(for itemID: String, on engine: any PlayerEngine) {
        Task { [weak self] in
            guard let self else { return }
            if let savedTime = await self.playbackStore.playbackPosition(for: itemID),
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
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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

        if fallbackKind == .extended, let directSMBURL {
            resolvedMediaURL = directSMBURL
            mount(url: directSMBURL, kind: .extended)
            return
        }

        mount(url: url, kind: fallbackKind)
    }

    private func mount(url: URL, kind: PlayerEngineKind, playerItem: AVPlayerItem? = nil) {
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

    private func loadSMBVideo(
        sourceID: String,
        share: String,
        path: String,
        fileName: String,
        totalSize: Int64,
        itemID: String,
        preferredKind: PlayerEngineKind
    ) {
        playbackState = .loading
        mediaLoadTask = Task { [weak self] in
            guard let self, !Task.isCancelled, self.currentItem.id == itemID else { return }

            guard let sharesSource = await self.resolver.resolve(sourceID: sourceID) as? SharesMediaSource else {
                self.playbackState = .failed("Unable to resolve SMB server connection.")
                self.errorMessage = "Unable to resolve SMB server connection."
                return
            }

            guard let resolvedSMBURL = VLCPlaybackOptions.makeSMBURL(
                host: sharesSource.server.host,
                share: share,
                relativePath: path
            ) else {
                self.playbackState = .failed("Unable to construct direct SMB playback URL.")
                self.errorMessage = "Unable to construct direct SMB playback URL."
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
                asset.resourceLoader.setDelegate(delegate, queue: Self.smbResourceLoaderQueue)
                Task { [weak self] in
                    guard let self, !Task.isCancelled, self.currentItem.id == itemID else { return }
                    await self.thumbnailProvider.registerAsset(asset, forAssetKey: itemID)
                }

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

    public func tearDown() {
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
        autoHideTask?.cancel()
        autoHideTask = nil
        progressPersistenceTask?.cancel()
        progressPersistenceTask = nil
        nativeEngine.tearDown()
        extendedEngine.tearDown()
        syncState(from: activeEngine)
    }
}
