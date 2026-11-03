//
//  VideoPlayerController.swift
//  fichier
//

import SwiftUI
import AVKit
import Observation
import OSLog

@Observable
@MainActor
public final class VideoPlayerController {
    public let manager: StorageLocationManager
    public let videos: [MediaItem]
    public var currentItem: MediaItem
    public private(set) var currentlyLoadedItem: MediaItem?
    
    public private(set) var player: AVPlayer?
    private var currentAsset: AVURLAsset?
    private var loaderDelegate: SMBResourceLoaderDelegate?
    
    public var playbackState: VideoPlaybackState = .idle
    public var errorMessage: String? = nil
    
    public var currentPlaybackSeconds: Double = 0
    public var totalDurationSeconds: Double = 0
    public var volume: Double = 1.0
    public var isMuted: Bool = false
    public var showControls: Bool = true
    
    public var isPiPActive: Bool = false
    public let pipCoordinator = CustomVideoPlayerCoordinator()
    public let trackManager = VideoTrackManager()
    public let seekCoordinator = VideoSeekCoordinator()
    
    public var isSaving: Bool = false
    public var saveStatusMessage: String? = nil
    public var shareableVideoURL: URL? = nil
    public var resumedToastMessage: String? = nil
    
    public var didRestorePlaybackPosition: Bool = false
    public var restoredFromSeconds: Double? = nil
    public var playbackStartTime: Date = Date()
    
    private var hideControlsTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var resumeBannerTask: Task<Void, Never>?
    private var periodicTimeObserverToken: Any?
    
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
    
    public var currentIndex: Int {
        videos.firstIndex(where: { $0.id == currentItem.id }) ?? 0
    }
    
    public func loadItem(_ item: MediaItem) {
        setupPlayer(for: item)
    }
    
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
        
        // 1. If local file or cached locally, play immediately from file
        if let localURL = item.localURL ?? (MediaCacheManager.shared.hasCachedVideo(for: item) ? MediaCacheManager.shared.localVideoURL(for: item) : nil) {
            self.shareableVideoURL = localURL
            let avPlayer = AVPlayer(url: localURL)
            self.player = avPlayer
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
                    let avPlayer = AVPlayer(url: videoURL)
                    self.player = avPlayer
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
            
            let queue = DispatchQueue(label: "com.acme.ios.photos.videoloader.\(uniqueID)", qos: .userInitiated)
            asset.resourceLoader.setDelegate(delegate, queue: queue)
            
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 2.0
            let avPlayer = AVPlayer(playerItem: playerItem)
            avPlayer.automaticallyWaitsToMinimizeStalling = true
            self.player = avPlayer
            self.playbackState = .buffering
            configurePlayer(avPlayer, for: validItem, loadTracksImmediately: false)
            avPlayer.play()
            startContinuousPlaybackMonitoring(for: avPlayer)
        }
    }
    
    private func configurePlayer(_ avPlayer: AVPlayer, for item: MediaItem, loadTracksImmediately: Bool) {
        self.volume = Double(avPlayer.volume)
        self.isMuted = avPlayer.isMuted
        
        // 1. Resume saved position if available
        if let savedSeconds = VideoPlaybackStore.shared.position(for: item) {
            let knownDuration = avPlayer.currentItem?.duration.seconds ?? 0
            if knownDuration.isFinite && knownDuration > 0 && (savedSeconds >= knownDuration - 4.0 || savedSeconds / knownDuration >= 0.90) {
                self.currentPlaybackSeconds = 0
                self.didRestorePlaybackPosition = false
                self.restoredFromSeconds = nil
            } else {
                let targetTime = CMTime(seconds: savedSeconds, preferredTimescale: 600)
                avPlayer.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
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
    
    private func startContinuousPlaybackMonitoring(for avPlayer: AVPlayer) {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor [weak self, weak avPlayer] in
            var tracksLoaded = false
            var waitingStartTime: Date? = nil
            
            while !Task.isCancelled {
                guard let self, let p = avPlayer else { break }
                let currentItem = p.currentItem
                
                // 1. Terminal error check
                let playbackError = p.error ?? currentItem?.error
                if playbackError != nil || p.status == .failed || currentItem?.status == .failed {
                    let desc = playbackError?.localizedDescription ?? "Playback error"
                    let sanitized = self.sanitizeErrorDescription(desc)
                    let localizedDesc = String(localized: .Strings.videoPlayerErrorPlayback(sanitized))
                    self.errorMessage = localizedDesc
                    self.playbackState = .failed(localizedDesc)
                    break
                }
                
                // 2. Load audio/subtitle tracks once playerItem is ready
                if !tracksLoaded, let item = currentItem, item.status == .readyToPlay {
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.playbackState = .paused
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
    
    public func togglePlayPause() {
        guard let player = player else { return }
        if player.timeControlStatus != .paused {
            player.pause()
            playbackState = .paused
            hideControlsTask?.cancel()
            withAnimation(.easeInOut(duration: 0.35)) {
                showControls = true
            }
        } else {
            if totalDurationSeconds > 1.0 && currentPlaybackSeconds >= totalDurationSeconds - 0.5 {
                seekTo(0, resumePlaying: true)
                currentPlaybackSeconds = 0
            } else {
                player.play()
                playbackState = .playing
                scheduleControlsAutoHide()
            }
        }
    }
    
    public func play() {
        guard let player = player, player.timeControlStatus == .paused else { return }
        player.play()
        playbackState = .playing
        scheduleControlsAutoHide()
    }
    
    public func pause() {
        guard let player = player, player.timeControlStatus != .paused else { return }
        player.pause()
        playbackState = .paused
        hideControlsTask?.cancel()
    }
    
    public func seekTo(_ targetSeconds: Double, resumePlaying: Bool = false) {
        finishSeeking(at: targetSeconds, resumePlaying: resumePlaying)
    }
    
    public func seekRelative(_ deltaSeconds: Double) {
        let current = currentPlaybackSeconds
        let dur = totalDurationSeconds > 0 ? totalDurationSeconds : (player?.currentItem?.duration.seconds ?? 0)
        let maxLimit = dur > 0 ? dur : max(current + deltaSeconds, 0)
        let newTarget = min(max(0, current + deltaSeconds), maxLimit)
        let resume = (player?.timeControlStatus != .paused) || playbackState.isPlaying
        seekTo(newTarget, resumePlaying: resume)
        withAnimation {
            showControls = true
        }
        scheduleControlsAutoHide()
    }
    
    public func finishSeeking(at targetSeconds: Double, resumePlaying: Bool) {
        didRestorePlaybackPosition = false
        restoredFromSeconds = nil
        currentPlaybackSeconds = targetSeconds
        
        if resumePlaying {
            playbackState = .buffering
        }
        
        seekCoordinator.finishSeeking(
            at: targetSeconds,
            resumePlaying: resumePlaying,
            player: player,
            onBuffering: { [weak self] buffering in
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if buffering {
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
    
    public func onTimelineSeek(targetSeconds: Double) {
        finishSeeking(at: targetSeconds, resumePlaying: seekCoordinator.wasPlayingBeforeScrub)
    }
    
    public func onTimelineScrubbing(targetSeconds: Double) {
        currentPlaybackSeconds = targetSeconds
        seekCoordinator.requestLiveFrameSeek(to: targetSeconds, player: player)
    }
    
    public func onTimelineScrubStateChanged(isScrubbing: Bool) {
        if isScrubbing {
            guard !seekCoordinator.isScrubbingTimeline else { return }
            seekCoordinator.startTimelineScrubbing(
                currentPlaybackSeconds: currentPlaybackSeconds,
                isPlaying: playbackState.isPlaying,
                player: player
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
    
    public func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        withAnimation {
            showControls = true
        }
        scheduleControlsAutoHide()
    }
    
    public func adjustVolume(by delta: Double) {
        let newVol = min(max(0.0, volume + delta), 1.0)
        volume = newVol
        isMuted = false
        player?.isMuted = false
        player?.volume = Float(newVol)
        withAnimation {
            showControls = true
        }
        scheduleControlsAutoHide()
    }
    
    public func goToNext() {
        guard !videos.isEmpty else { return }
        let nextIndex = (currentIndex + 1) % videos.count
        withAnimation(.easeInOut(duration: 0.3)) {
            currentItem = videos[nextIndex]
        }
    }
    
    public func playNextVideo() {
        guard videos.count > 1 else { return }
        let nextIndex = currentIndex + 1
        if nextIndex < videos.count {
            withAnimation(.easeInOut) {
                currentItem = videos[nextIndex]
            }
        }
    }
    
    public func goToPrevious() {
        guard !videos.isEmpty else { return }
        let prevIndex = (currentIndex - 1 + videos.count) % videos.count
        withAnimation(.easeInOut(duration: 0.3)) {
            currentItem = videos[prevIndex]
        }
    }
    
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
    
    public func restartVideo() {
        guard player != nil else { return }
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
    
    public func cancelAutoHideTimer() {
        hideControlsTask?.cancel()
        hideControlsTask = nil
    }
    
    public func resetAutoHideTimer() {
        if showControls && playbackState.isPlaying {
            scheduleControlsAutoHide()
        }
    }
    
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
    
    public func handleTwoFingerTap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        togglePlayPause()
    }
    
    public func tearDownPlayer(deactivateAudioSession: Bool = false) {
        if let p = player, let current = p.currentItem, let loadedItem = currentlyLoadedItem {
            let secs = p.currentTime().seconds
            let dur = current.duration.seconds
            if secs.isFinite && !secs.isNaN && dur.isFinite && !dur.isNaN && secs >= 2.0 {
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
    
    public func handleItemDidPlayToEndTime(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem,
              let current = player?.currentItem,
              item == current else { return }
        
        let targetItem = currentlyLoadedItem ?? currentItem
        
        if didRestorePlaybackPosition && (totalDurationSeconds > 3.0 || totalDurationSeconds == 0) {
            didRestorePlaybackPosition = false
            restoredFromSeconds = nil
            player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            currentPlaybackSeconds = 0
            VideoPlaybackStore.shared.clearPosition(for: targetItem)
            player?.play()
            playbackState = .playing
            return
        }
        
        didRestorePlaybackPosition = false
        restoredFromSeconds = nil
        
        if totalDurationSeconds >= 2.0 && currentPlaybackSeconds >= totalDurationSeconds * 0.9 {
            VideoPlaybackStore.shared.markFinished(for: targetItem, duration: totalDurationSeconds)
        }
        playNextVideo()
    }
    
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
    
    public func handleScenePhaseBackground() {
        if let p = player, let loadedItem = currentlyLoadedItem {
            let secs = p.currentTime().seconds
            let dur = p.currentItem?.duration.seconds ?? 0
            VideoPlaybackStore.shared.savePosition(secs, duration: dur, for: loadedItem)
        }
        VideoPlaybackStore.shared.flush()
    }
    
    // MARK: - Error Sanitization
    
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
