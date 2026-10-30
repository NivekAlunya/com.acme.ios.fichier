//
//  VideoDetailView.swift
//  fichier
//

import SwiftUI
import AVKit

public struct VideoDetailView: View {
    var manager: SMBDirectManager
    let videos: [SMBItem]
    let initialItem: SMBItem
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentItem: SMBItem
    @State private var player: AVPlayer?
    @State private var loaderDelegate: SMBResourceLoaderDelegate?
    @State private var isBuffering = true
    @State private var errorMessage: String?
    @State private var showControls: Bool = true
    @State private var isSaving: Bool = false
    @State private var saveStatusMessage: String?
    @State private var monitorTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?
    @State private var previewThumbnail: UIImage?
    
    // Playback Enhancements: Resume, Audio/Subtitles/Speed, PiP, AirPlay, Timeline, Volume
    @State private var trackManager = VideoTrackManager()
    @State private var resumedToastMessage: String?
    @State private var periodicTimeObserverToken: Any?
    @State private var resumeBannerTask: Task<Void, Never>?
    @State private var isPiPActive: Bool = false
    @State private var pipCoordinator: CustomVideoPlayerCoordinator?
    @State private var currentPlaybackSeconds: Double = 0
    @State private var totalDurationSeconds: Double = 0
    @State private var isPlaying: Bool = true
    @State private var volume: Double = 1.0
    @State private var isMuted: Bool = false
    @State private var hideControlsTask: Task<Void, Never>?
    
    // Swipe for Seeking Gesture State
    @State private var isScrubbingWithGesture: Bool = false
    @State private var initialScrubTime: Double = 0
    @State private var wasPlayingBeforeScrub: Bool = false
    @State private var isSeekingFrame: Bool = false
    @State private var pendingSeekSeconds: Double? = nil
    @State private var lastSeekTime: Date = Date.distantPast
    
    public init(
        manager: SMBDirectManager,
        videos: [SMBItem],
        initialItem: SMBItem
    ) {
        self.manager = manager
        let vids = videos.filter { $0.isVideo }
        self.videos = vids.isEmpty ? [initialItem] : vids
        self.initialItem = initialItem
        self._currentItem = State(initialValue: initialItem)
    }
    
    private var currentIndex: Int {
        videos.firstIndex(where: { $0.id == currentItem.id }) ?? 0
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Custom Video Player (Native UI disabled, custom controls enabled)
            if let player {
                CustomVideoPlayerView(
                    player: player,
                    showsPlaybackControls: false,
                    onPiPStatusChanged: { isActive in
                        self.isPiPActive = isActive
                    },
                    onCoordinatorReady: { coordinator in
                        self.pipCoordinator = coordinator
                    }
                )
                .ignoresSafeArea()
            } else if let previewThumbnail {
                Image(uiImage: previewThumbnail)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            }
            
            // Buffering Spinner
            if isBuffering && errorMessage == nil {
                VStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                    Text(.Strings.videoPlayerBuffering)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .transition(.opacity)
            }
            
            // Error Message
            if let error = errorMessage {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button(.Strings.commonRetry) {
                        setupPlayer(for: currentItem)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            
            // Custom Controls Overlay (Top HUD, Center Play/Pause, Side Navigation, Bottom Timeline)
            ZStack {
                VStack {
                    topBar
                    Spacer()
                    bottomControls
                }
                
                // Center Play / Pause Toggle
                if !isBuffering && errorMessage == nil {
                    Button {
                        togglePlayPause()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                
                // Side Navigation Arrows
                if videos.count > 1 {
                    HStack {
                        Button {
                            goToPrevious()
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 42))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                        }
                        .padding(.leading, 18)
                        
                        Spacer()
                        
                        Button {
                            goToNext()
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 42))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                        }
                        .padding(.trailing, 18)
                    }
                }
            }
            .opacity(showControls ? 1 : 0)
            .animation(.easeInOut(duration: 0.35), value: showControls)
            .animation(.easeInOut(duration: 0.25), value: isBuffering)
            .allowsHitTesting(showControls)
            
            // Save Toast Banner
            if let message = saveStatusMessage {
                VStack {
                    Spacer().frame(height: 70)
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(message)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
            }
            
            // Resume Playback Toast Banner
            if let message = resumedToastMessage {
                VStack {
                    Spacer().frame(height: 70)
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .foregroundColor(.blue)
                        Text(message)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Button {
                            restartVideo()
                        } label: {
                            Text(.Strings.videoPlayerRestartButton)
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.blue))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isBuffering)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .contentShape(Rectangle())
        .simultaneousGesture(videoSeekGesture)
        .onTapGesture {
            guard !isScrubbingWithGesture else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                showControls.toggle()
            }
            if showControls {
                scheduleControlsAutoHide()
            } else {
                hideControlsTask?.cancel()
            }
        }
        .task(id: currentItem.id) {
            setupPlayer(for: currentItem)
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  let current = player?.currentItem,
                  item == current else { return }
            VideoPlaybackStore.shared.markFinished(for: currentItem, duration: totalDurationSeconds)
            playNextVideo()
        }
        .onDisappear {
            guard !isPiPActive else { return }
            tearDownPlayer()
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            // Close Button (Lonely at top leading)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            
            Spacer()
            
            // Sound Level Bar at top trailing
            VideoVolumeBar(volume: $volume, isMuted: $isMuted)
                .padding(.trailing, 16)
                .onChange(of: volume) { _, newVol in
                    player?.volume = Float(newVol)
                    resetAutoHideTimer()
                }
                .onChange(of: isMuted) { _, muted in
                    player?.isMuted = muted
                    resetAutoHideTimer()
                }
        }
        .overlay(alignment: .center) {
            // Center Tools Capsule
            HStack(spacing: 8) {
                // 1. Previous Video
                if videos.count > 1 {
                    Button {
                        goToPrevious()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                    }
                }
                
                // 2. Title & Counter
                VStack(spacing: 1) {
                    Text(currentItem.name)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: 100)
                    
                    Text(.Strings.commonItemCounterAndSize(currentIndex + 1, videos.count, currentItem.formattedSize))
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // 3. Next Video
                if videos.count > 1 {
                    Button {
                        goToNext()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                    }
                }
                
                Divider()
                    .frame(height: 18)
                    .background(Color.white.opacity(0.3))
                
                // 4. Favorite Button
                Button {
                    FavoritesManager.shared.toggleFavorite(currentItem)
                } label: {
                    Image(systemName: FavoritesManager.shared.isFavorite(currentItem) ? "heart.fill" : "heart")
                        .font(.system(size: 13))
                        .foregroundStyle(FavoritesManager.shared.isFavorite(currentItem) ? Color.red : Color.white)
                        .padding(4)
                }
                
                // 5. Save to Camera Roll
                Button {
                    saveToCameraRoll()
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.65)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .padding(4)
                    }
                }
                .disabled(isSaving)
                
                // 6. ShareLink
                if MediaCacheManager.shared.hasCachedVideo(for: currentItem) {
                    ShareLink(
                        item: MediaCacheManager.shared.localVideoURL(for: currentItem),
                        preview: SharePreview(currentItem.name)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .padding(4)
                    }
                }
                
                // 7. Quick Subtitle Toggle Button
                if !trackManager.availableSubtitles.isEmpty {
                    Button {
                        if let item = player?.currentItem {
                            trackManager.toggleSubtitles(in: item)
                        }
                    } label: {
                        Image(systemName: trackManager.isSubtitlesEnabled ? "captions.bubble.fill" : "captions.bubble")
                            .font(.system(size: 13))
                            .foregroundStyle(trackManager.isSubtitlesEnabled ? Color.blue : Color.white)
                            .padding(4)
                    }
                }
                
                // 8. Playback Options Menu (Speed, Audio, Subtitles)
                Menu {
                    // Playback Speed
                    Section(.Strings.videoPlayerMenuPlaybackSpeed) {
                        ForEach(VideoPlaybackRate.allCases) { rate in
                            Button {
                                if let p = player {
                                    trackManager.setPlaybackRate(rate, for: p)
                                }
                            } label: {
                                HStack {
                                    Text(rate.displayName)
                                    if trackManager.playbackRate == rate {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    
                    // Audio Tracks
                    if trackManager.availableAudios.count > 1 {
                        Section(.Strings.videoPlayerMenuAudio) {
                            ForEach(trackManager.availableAudios) { option in
                                Button {
                                    if let item = player?.currentItem {
                                        trackManager.selectAudio(option: option, in: item)
                                    }
                                } label: {
                                    HStack {
                                        Text(option.displayName)
                                        if trackManager.selectedAudioID == option.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Subtitles
                    if !trackManager.availableSubtitles.isEmpty {
                        Section(.Strings.videoPlayerMenuSubtitles) {
                            ForEach(trackManager.availableSubtitles) { option in
                                Button {
                                    if let item = player?.currentItem {
                                        trackManager.selectSubtitle(option: option, in: item)
                                    }
                                } label: {
                                    HStack {
                                        Text(option.displayName)
                                        if trackManager.selectedSubtitleID == option.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .padding(4)
                }
                
                // 9. Picture-in-Picture Button
                Button {
                    pipCoordinator?.togglePiP()
                } label: {
                    Image(systemName: isPiPActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 13))
                        .foregroundStyle(isPiPActive ? Color.blue : Color.white)
                        .padding(4)
                }
                
                // 10. AirPlay Button
                AirPlayButtonView()
                    .frame(width: 22, height: 22)
                    .padding(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            )
        }
        .padding(.top, 10)
    }
    
    // MARK: - Bottom Controls (Compact Timeline Bar)
    
    private var bottomControls: some View {
        VideoTimelineBar(
            currentTime: currentPlaybackSeconds,
            duration: totalDurationSeconds,
            onSeek: { targetSeconds in
                finishSeeking(at: targetSeconds, resumePlaying: wasPlayingBeforeScrub)
            },
            onScrubbing: { targetSeconds in
                currentPlaybackSeconds = targetSeconds
                requestLiveFrameSeek(to: targetSeconds)
            },
            onScrubStateChanged: { isScrubbing in
                if isScrubbing {
                    hideControlsTask?.cancel()
                    wasPlayingBeforeScrub = (player?.timeControlStatus == .playing)
                    if wasPlayingBeforeScrub {
                        player?.pause()
                        isPlaying = false
                    }
                } else {
                    scheduleControlsAutoHide()
                }
            }
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
    
    // MARK: - Swipe for Seeking (Controls timeline bar without popup HUD)
    
    private var videoSeekGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                let hTranslation = value.translation.width
                let vTranslation = value.translation.height
                
                guard abs(hTranslation) > abs(vTranslation) else { return }
                guard let player = player else { return }
                
                if !isScrubbingWithGesture {
                    isScrubbingWithGesture = true
                    hideControlsTask?.cancel()
                    wasPlayingBeforeScrub = (player.timeControlStatus == .playing)
                    if wasPlayingBeforeScrub {
                        player.pause()
                        isPlaying = false
                    }
                    initialScrubTime = currentPlaybackSeconds
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showControls = true
                    }
                }
                
                let sensitivity: Double
                if totalDurationSeconds > 3600 {
                    sensitivity = 2.0
                } else if totalDurationSeconds > 600 {
                    sensitivity = 1.0
                } else {
                    sensitivity = 0.5
                }
                
                let delta = Double(hTranslation) * sensitivity
                let target = max(0, min(totalDurationSeconds > 0 ? totalDurationSeconds : initialScrubTime + delta, initialScrubTime + delta))
                currentPlaybackSeconds = target
                requestLiveFrameSeek(to: target)
            }
            .onEnded { value in
                guard isScrubbingWithGesture else { return }
                isScrubbingWithGesture = false
                finishSeeking(at: currentPlaybackSeconds, resumePlaying: wasPlayingBeforeScrub)
            }
    }
    
    // MARK: - Live Frame Seeking While Scrubbing
    
    private func requestLiveFrameSeek(to targetSeconds: Double) {
        guard let player = player else { return }
        
        guard !isSeekingFrame else {
            pendingSeekSeconds = targetSeconds
            return
        }
        
        let now = Date()
        if now.timeIntervalSince(lastSeekTime) < 0.06 {
            pendingSeekSeconds = targetSeconds
            return
        }
        
        isSeekingFrame = true
        lastSeekTime = now
        
        let targetCM = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 1.0, preferredTimescale: 600)
        
        player.seek(to: targetCM, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in
            Task { @MainActor in
                self.isSeekingFrame = false
                if let nextTarget = self.pendingSeekSeconds {
                    self.pendingSeekSeconds = nil
                    self.requestLiveFrameSeek(to: nextTarget)
                }
            }
        }
    }
    
    private func finishSeeking(at targetSeconds: Double, resumePlaying: Bool) {
        pendingSeekSeconds = nil
        isSeekingFrame = false
        seekTo(targetSeconds)
        if resumePlaying {
            player?.play()
            isPlaying = true
        }
        scheduleControlsAutoHide()
    }
    
    // MARK: - Auto-Hide Controls
    
    private func scheduleControlsAutoHide(delay: Double = 3.5) {
        hideControlsTask?.cancel()
        guard showControls && isPlaying && !isScrubbingWithGesture else { return }
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls = false
            }
        }
    }
    
    private func resetAutoHideTimer() {
        if showControls && isPlaying {
            scheduleControlsAutoHide()
        }
    }
    
    // MARK: - Transport Actions
    
    private func togglePlayPause() {
        guard let player = player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
            hideControlsTask?.cancel()
            withAnimation(.easeInOut(duration: 0.35)) {
                showControls = true
            }
        } else {
            player.play()
            isPlaying = true
            scheduleControlsAutoHide()
        }
    }
    
    private func seekTo(_ targetSeconds: Double) {
        guard let player = player else { return }
        let targetCM = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: targetCM, toleranceBefore: .zero, toleranceAfter: .zero)
        currentPlaybackSeconds = targetSeconds
    }
    
    private func goToNext() {
        guard !videos.isEmpty else { return }
        let nextIndex = (currentIndex + 1) % videos.count
        withAnimation(.easeInOut(duration: 0.3)) {
            currentItem = videos[nextIndex]
        }
    }
    
    private func playNextVideo() {
        guard videos.count > 1 else { return }
        let nextIndex = currentIndex + 1
        if nextIndex < videos.count {
            withAnimation(.easeInOut) {
                currentItem = videos[nextIndex]
            }
        }
    }
    
    private func goToPrevious() {
        guard !videos.isEmpty else { return }
        let prevIndex = (currentIndex - 1 + videos.count) % videos.count
        withAnimation(.easeInOut(duration: 0.3)) {
            currentItem = videos[prevIndex]
        }
    }
    
    private func saveToCameraRoll() {
        isSaving = true
        Task {
            do {
                let localURL = try await manager.fetchVideoURL(for: currentItem)
                try await PhotoLibrarySaver.saveVideoToPhotos(at: localURL)
                withAnimation {
                    saveStatusMessage = String(localized: .Strings.videoPlayerSavedToPhotos)
                }
            } catch {
                withAnimation {
                    saveStatusMessage = String(localized: .Strings.commonErrorFailedToSave(error.localizedDescription))
                }
            }
            isSaving = false
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation {
                saveStatusMessage = nil
            }
        }
    }
    
    private func tearDownPlayer() {
        if let p = player, let current = p.currentItem {
            let secs = p.currentTime().seconds
            let dur = current.duration.seconds
            if secs.isFinite && !secs.isNaN && dur.isFinite && !dur.isNaN {
                VideoPlaybackStore.shared.savePosition(secs, duration: dur, for: currentItem)
            }
        }
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
        loadTask?.cancel()
        loadTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        loaderDelegate?.cancelAll()
        loaderDelegate = nil
        isScrubbingWithGesture = false
        isSeekingFrame = false
        pendingSeekSeconds = nil
        player?.pause()
        player = nil
        isBuffering = true
        errorMessage = nil
    }
    
    private func restartVideo() {
        guard let player = player else { return }
        resumeBannerTask?.cancel()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        currentPlaybackSeconds = 0
        VideoPlaybackStore.shared.clearPosition(for: currentItem)
        withAnimation {
            resumedToastMessage = nil
        }
    }
    
    private func showResumeBanner(at savedSeconds: Double) {
        resumeBannerTask?.cancel()
        withAnimation {
            resumedToastMessage = String(localized: .Strings.videoPlayerResumeToast(formatSeconds(savedSeconds)))
        }
        resumeBannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.0))
            guard !Task.isCancelled else { return }
            withAnimation {
                resumedToastMessage = nil
            }
        }
    }
    
    private func formatSeconds(_ totalSeconds: Double) -> String {
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
    
    private func setupPlayer(for item: SMBItem) {
        tearDownPlayer()
        
        // Show immediate preview frame while video buffers
        Task { @MainActor in
            self.previewThumbnail = await manager.downloadThumbnail(for: item, maxDimension: 600)
        }
        
        // Configure audio session asynchronously off the main thread to prevent UI hangs
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback {
                try? session.setCategory(.playback, mode: .moviePlayback)
            }
            try? session.setActive(true)
        }
        
        // 1. If previously downloaded/cached locally, play immediately from file
        if MediaCacheManager.shared.hasCachedVideo(for: item) {
            let localURL = MediaCacheManager.shared.localVideoURL(for: item)
            let avPlayer = AVPlayer(url: localURL)
            self.player = avPlayer
            self.isBuffering = false
            configurePlayer(avPlayer, for: item)
            avPlayer.play()
            self.scheduleControlsAutoHide()
            return
        }
        
        // 2. Progressive On-Demand Stream via SMBResourceLoaderDelegate
        loadTask = Task { @MainActor in
            var validItem = item
            if validItem.size <= 0 {
                let realSize = await manager.fetchFileSize(for: item)
                if realSize > 0 {
                    validItem = SMBItem(
                        name: item.name,
                        shareName: item.shareName,
                        path: item.path,
                        isDirectory: item.isDirectory,
                        size: realSize,
                        modifiedDate: item.modifiedDate
                    )
                }
            }
            
            guard !Task.isCancelled else { return }
            
            let uniqueID = UUID().uuidString
            let safeName = validItem.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "video.mp4"
            guard let streamURL = URL(string: "smbstream://localhost/\(uniqueID)/\(safeName)") else {
                self.errorMessage = String(localized: .Strings.videoPlayerErrorInvalidStreamUrl)
                self.isBuffering = false
                return
            }
            
            let asset = AVURLAsset(url: streamURL)
            let delegate = SMBResourceLoaderDelegate(worker: self.manager.clientActor, item: validItem)
            self.loaderDelegate = delegate
            
            let queue = DispatchQueue(label: "com.acme.ios.photos.videoloader.\(uniqueID)", qos: .userInitiated)
            asset.resourceLoader.setDelegate(delegate, queue: queue)
            
            let playerItem = AVPlayerItem(asset: asset)
            let avPlayer = AVPlayer(playerItem: playerItem)
            avPlayer.automaticallyWaitsToMinimizeStalling = true
            self.player = avPlayer
            configurePlayer(avPlayer, for: validItem)
            avPlayer.play()
            
            // Monitor playback readiness
            self.monitorTask?.cancel()
            self.monitorTask = Task { @MainActor [weak avPlayer] in
                while !Task.isCancelled {
                    guard let p = avPlayer else { break }
                    if p.timeControlStatus == .playing {
                        self.isBuffering = false
                        self.isPlaying = true
                        if let item = p.currentItem {
                            await self.trackManager.loadTracks(for: item)
                        }
                        self.scheduleControlsAutoHide()
                        break
                    }
                    if let err = p.currentItem?.error {
                        self.errorMessage = String(localized: .Strings.videoPlayerErrorPlayback(err.localizedDescription))
                        self.isBuffering = false
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
        }
    }
    
    private func configurePlayer(_ avPlayer: AVPlayer, for item: SMBItem) {
        // Sync volume & mute state
        self.volume = Double(avPlayer.volume)
        self.isMuted = avPlayer.isMuted
        self.isPlaying = true
        
        // 1. Resume saved position if available
        if let savedSeconds = VideoPlaybackStore.shared.position(for: item) {
            let targetTime = CMTime(seconds: savedSeconds, preferredTimescale: 600)
            avPlayer.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            self.currentPlaybackSeconds = savedSeconds
            showResumeBanner(at: savedSeconds)
        } else {
            self.currentPlaybackSeconds = 0
        }
        
        // 2. Set playback rate
        trackManager.setPlaybackRate(trackManager.playbackRate, for: avPlayer)
        
        // 3. Load media tracks (audio / subtitles)
        if let currentItem = avPlayer.currentItem {
            Task { @MainActor in
                await trackManager.loadTracks(for: currentItem)
            }
        }
        
        // 4. Periodic time observer to remember playback progress & update timeline
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        self.periodicTimeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak avPlayer] time in
            guard let p = avPlayer, let current = p.currentItem else { return }
            let secs = time.seconds
            let dur = current.duration.seconds
            
            if secs.isFinite && !secs.isNaN {
                self.currentPlaybackSeconds = secs
            }
            if dur.isFinite && !dur.isNaN && dur > 0 {
                self.totalDurationSeconds = dur
            }
            self.isPlaying = (p.timeControlStatus == .playing)
            
            if secs.isFinite && !secs.isNaN && dur.isFinite && !dur.isNaN {
                VideoPlaybackStore.shared.savePosition(secs, duration: dur, for: item)
            }
        }
    }
}
