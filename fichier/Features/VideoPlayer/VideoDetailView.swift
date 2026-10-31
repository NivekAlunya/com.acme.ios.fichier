//
//  VideoDetailView.swift
//  fichier
//

import SwiftUI
import AVKit
import OSLog

public struct VideoDetailView: View {
    var manager: SMBDirectManager
    let videos: [SMBItem]
    let initialItem: SMBItem
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var currentItem: SMBItem
    @State private var currentlyLoadedItem: SMBItem?
    @State private var playbackStartTime: Date = Date()
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
    @State private var pipCoordinator = CustomVideoPlayerCoordinator()
    @State private var currentPlaybackSeconds: Double = 0
    @State private var totalDurationSeconds: Double = 0
    @State private var isPlaying: Bool = true
    @State private var volume: Double = 1.0
    @State private var isMuted: Bool = false
    @State private var hideControlsTask: Task<Void, Never>?
    
    // Swipe for Seeking Gesture State
    @State private var isScrubbingWithGesture: Bool = false
    @State private var isScrubbingTimeline: Bool = false
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
                    coordinator: pipCoordinator,
                    onPiPStatusChanged: { isActive in
                        self.isPiPActive = isActive
                    },
                    onTwoFingerTap: {
                        handleTwoFingerTap()
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
            
            // Active Subtitle Text Overlay
            if !trackManager.currentSubtitleText.isEmpty && trackManager.isSubtitlesEnabled {
                VStack {
                    Spacer()
                    Text(trackManager.currentSubtitleText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                        .padding(.horizontal, 32)
                        .padding(.bottom, showControls ? 68 : 24)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.2), value: showControls)
                }
                .transition(.opacity)
            }
            
            // Custom Controls Overlay (Top HUD, Center Play/Pause, Side Navigation, Bottom Timeline)
            ZStack {
                VStack(spacing: 12) {
                    topBar
                    
                    if let message = resumedToastMessage {
                        resumeToastView(message: message)
                    }
                    
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
        }
        .animation(.easeInOut(duration: 0.25), value: isBuffering)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .contentShape(Rectangle())
        .simultaneousGesture(videoSeekGesture)
        .onTapGesture {
            guard !isScrubbingWithGesture && !isScrubbingTimeline else { return }
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
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  let current = player?.currentItem,
                  item == current else { return }
            
            let targetItem = currentlyLoadedItem ?? currentItem
            
            // If the video reached end-of-play within 2.0 seconds of starting playback,
            // it was likely restored right at the end (or near EOF).
            // In that case, DO NOT skip to the next video!
            // Instead, rewind to 0:00 and let the user watch the video from the beginning.
            if Date().timeIntervalSince(playbackStartTime) < 2.0 {
                player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                currentPlaybackSeconds = 0
                VideoPlaybackStore.shared.clearPosition(for: targetItem)
                player?.play()
                isPlaying = true
                return
            }
            
            if totalDurationSeconds >= 2.0 && currentPlaybackSeconds >= totalDurationSeconds * 0.9 {
                VideoPlaybackStore.shared.markFinished(for: targetItem, duration: totalDurationSeconds)
            }
            playNextVideo()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // Persist the latest playback position right before the app may be suspended
                if let p = player, let loadedItem = currentlyLoadedItem {
                    let secs = p.currentTime().seconds
                    let dur = p.currentItem?.duration.seconds ?? 0
                    VideoPlaybackStore.shared.savePosition(secs, duration: dur, for: loadedItem)
                }
                VideoPlaybackStore.shared.flush()
            }
        }
        .onDisappear {
            guard !isPiPActive && scenePhase == .active else { return }
            tearDownPlayer()
        }
    }
    
    // MARK: - Top Bar
    
    private var isRegular: Bool {
        horizontalSizeClass == .regular
    }
    
    private var isCompactPortrait: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    
    // MARK: - Close Button
    
    private var closeButton: some View {
        Button {
            tearDownPlayer()
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
    }
    
    // MARK: - Sound Volume Bar
    
    private var volumeBar: some View {
        VideoVolumeBar(volume: $volume, isMuted: $isMuted)
            .onChange(of: volume) { _, newVol in
                player?.volume = Float(newVol)
                resetAutoHideTimer()
            }
            .onChange(of: isMuted) { _, muted in
                player?.isMuted = muted
                resetAutoHideTimer()
            }
    }
    
    // MARK: - Title & Item Counter Capsule
    
    private var titleCapsule: some View {
        HStack(spacing: 6) {
            Text(currentItem.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 180)
            
            Text("•")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
            
            Text(.Strings.commonItemCounterAndSize(currentIndex + 1, videos.count, currentItem.formattedSize))
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial))
    }
    
    // MARK: - Navigation Buttons & Dividers
    
    private var previousButton: some View {
        Button {
            goToPrevious()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var nextButton: some View {
        Button {
            goToNext()
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var toolsDivider: some View {
        Divider()
            .frame(height: 22)
            .background(Color.white.opacity(0.3))
    }
    
    // MARK: - Playback Options Menu
    
    private var playbackOptionsMenu: some View {
        Menu {
            // Picture-in-Picture
            Button {
                pipCoordinator.togglePiP()
            } label: {
                Label(
                    isPiPActive ? String(localized: .Strings.videoPlayerMenuPipExit) : String(localized: .Strings.videoPlayerMenuPipEnter),
                    systemImage: isPiPActive ? "pip.exit" : "pip.enter"
                )
            }
            
            // Subtitles
            if !trackManager.availableSubtitles.isEmpty {
                Section(.Strings.videoPlayerMenuSubtitles) {
                    Button {
                        if let item = player?.currentItem {
                            trackManager.toggleSubtitles(in: item)
                        }
                    } label: {
                        Label(
                            trackManager.isSubtitlesEnabled ? String(localized: .Strings.videoPlayerMenuSubtitlesDisable) : String(localized: .Strings.videoPlayerMenuSubtitlesEnable),
                            systemImage: trackManager.isSubtitlesEnabled ? "captions.bubble.fill" : "captions.bubble"
                        )
                    }
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
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(trackManager.isSubtitlesEnabled || trackManager.playbackRate != .normal ? Color.blue : Color.white)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Action Tools Icons
    
    @ViewBuilder
    private func actionToolsIcons(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            // 1. Favorite Button
            Button {
                FavoritesManager.shared.toggleFavorite(currentItem)
            } label: {
                Image(systemName: FavoritesManager.shared.isFavorite(currentItem) ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(FavoritesManager.shared.isFavorite(currentItem) ? Color.red : Color.white)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // 2. Save to Camera Roll
            Button {
                saveToCameraRoll()
            } label: {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            
            // 3. ShareLink
            if MediaCacheManager.shared.hasCachedVideo(for: currentItem) {
                ShareLink(
                    item: MediaCacheManager.shared.localVideoURL(for: currentItem),
                    preview: SharePreview(currentItem.name)
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            // 4. AirPlay Button
            AirPlayButtonView()
                .frame(width: 22, height: 22)
                .frame(width: 30, height: 30)
            
            // 5. Playback Options Menu (Subtitles, Audio, Speed, PiP)
            playbackOptionsMenu
        }
    }
    
    // MARK: - Top Bar (Responsive for Compact Portrait vs Regular/Landscape)
    
    private var topBar: some View {
        Group {
            if isCompactPortrait {
                // Two-tier stacked layout for compact portrait (iPhone Portrait, ~375–393pt)
                VStack(spacing: 8) {
                    // Row 1: Close Button + Centered Title Capsule + Volume Bar
                    HStack(spacing: 8) {
                        closeButton
                        
                        Spacer(minLength: 4)
                        
                        titleCapsule
                        
                        Spacer(minLength: 4)
                        
                        volumeBar
                    }
                    .padding(.horizontal, 16)
                    
                    // Row 2: Centered Floating Action Pill
                    HStack(spacing: 6) {
                        if videos.count > 1 {
                            previousButton
                            toolsDivider
                        }
                        
                        actionToolsIcons(spacing: 12)
                        
                        if videos.count > 1 {
                            toolsDivider
                            nextButton
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                    )
                }
                .padding(.top, 10)
            } else {
                // Regular / Landscape layout: single row with centered overlay
                HStack {
                    closeButton
                        .padding(.leading, 16)
                    
                    Spacer()
                    
                    volumeBar
                        .padding(.trailing, 16)
                }
                .frame(minHeight: isRegular ? 84 : 64)
                .overlay(alignment: .center) {
                    centerToolsBar
                        .padding(.top, isRegular ? 20 : 0)
                }
                .padding(.top, isRegular ? 20 : 10)
            }
        }
    }
    
    // MARK: - Resume Playback Toast (Stacked below topBar)
    
    @ViewBuilder
    private func resumeToastView(message: String) -> some View {
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
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    // MARK: - Center Tools Toolbar (Regular / Landscape Single-Row Overlay)
    
    private var centerToolsBar: some View {
        HStack(spacing: 6) {
            // Previous Button (on leading side, larger)
            if videos.count > 1 {
                previousButton
                toolsDivider
            }
            
            // Middle: 2 Lines (Line 1: Title, Line 2: Tools)
            VStack(spacing: 4) {
                // Line 1: Title displaying more text & Counter/Size
                HStack(spacing: 6) {
                    Text(currentItem.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 180)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                    
                    Text(.Strings.commonItemCounterAndSize(currentIndex + 1, videos.count, currentItem.formattedSize))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                
                // Line 2: Consolidated & Enlarged Tools
                actionToolsIcons(spacing: 14)
            }
            .padding(.horizontal, 6)
            
            // Next Button (on trailing side, larger)
            if videos.count > 1 {
                toolsDivider
                nextButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        )
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
                isScrubbingTimeline = isScrubbing
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
                guard !isScrubbingTimeline else { return }
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
                guard !isScrubbingTimeline else { return }
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
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isBuffering = false
        }
        scheduleControlsAutoHide()
    }
    
    // MARK: - Auto-Hide Controls
    
    private func scheduleControlsAutoHide(delay: Double = 3.5) {
        guard showControls && isPlaying && !isBuffering && !isScrubbingWithGesture && !isScrubbingTimeline else {
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
    
    private func resetAutoHideTimer() {
        if showControls && isPlaying {
            scheduleControlsAutoHide()
        }
    }
    
    // MARK: - Transport Actions
    
    private func handleTwoFingerTap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        togglePlayPause()
    }
    
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
            if totalDurationSeconds > 1.0 && currentPlaybackSeconds >= totalDurationSeconds - 0.5 {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                currentPlaybackSeconds = 0
            }
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
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isBuffering = false
        }
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
        if let p = player, let current = p.currentItem, let loadedItem = currentlyLoadedItem {
            let secs = p.currentTime().seconds
            let dur = current.duration.seconds
            if secs.isFinite && !secs.isNaN && dur.isFinite && !dur.isNaN && secs >= 2.0 {
                VideoPlaybackStore.shared.savePosition(secs, duration: dur, for: loadedItem)
            }
        }
        currentlyLoadedItem = nil
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
        
        // Deactivate audio session in background so other apps' audio can resume
        Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    
    private func restartVideo() {
        guard let player = player else { return }
        let targetItem = currentlyLoadedItem ?? currentItem
        resumeBannerTask?.cancel()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        currentPlaybackSeconds = 0
        VideoPlaybackStore.shared.clearPosition(for: targetItem)
        withAnimation {
            resumedToastMessage = nil
        }
    }
    
    private func showResumeBanner(at savedSeconds: Double) {
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
        playbackStartTime = Date()
        tearDownPlayer()
        currentlyLoadedItem = item
        showControls = true
        
        // Show immediate preview frame while video buffers
        Task { @MainActor in
            self.previewThumbnail = await manager.downloadThumbnail(for: item, maxDimension: 600)
        }
        
        // Configure audio session asynchronously off the main thread to prevent UI hangs
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
            } catch {
                AppLog.player.error("Failed to activate audio session: \(error.localizedDescription)")
            }
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
                        connectionID: item.connectionID,
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
                    let isReady = p.timeControlStatus == .playing
                        || (p.currentItem?.status == .readyToPlay && (p.rate > 0 || p.currentItem?.isPlaybackLikelyToKeepUp == true))
                        || self.currentPlaybackSeconds > 0.05
                    
                    if isReady {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.isBuffering = false
                        }
                        self.isPlaying = (p.timeControlStatus != .paused)
                        if let item = p.currentItem {
                            Task { @MainActor in
                                await self.trackManager.loadTracks(for: item)
                            }
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
            let knownDuration = avPlayer.currentItem?.duration.seconds ?? 0
            if knownDuration.isFinite && knownDuration > 0 && (savedSeconds >= knownDuration - 4.0 || savedSeconds / knownDuration >= 0.90) {
                self.currentPlaybackSeconds = 0
            } else {
                let targetTime = CMTime(seconds: savedSeconds, preferredTimescale: 600)
                avPlayer.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
                self.currentPlaybackSeconds = savedSeconds
                showResumeBanner(at: savedSeconds)
            }
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
            MainActor.assumeIsolated {
                guard let p = avPlayer, let current = p.currentItem else { return }
                let secs = time.seconds
                let dur = current.duration.seconds
                
                if !self.isScrubbingWithGesture && !self.isScrubbingTimeline {
                    if secs.isFinite && !secs.isNaN {
                        self.currentPlaybackSeconds = secs
                    }
                }
                if dur.isFinite && !dur.isNaN && dur > 0 {
                    self.totalDurationSeconds = dur
                }
                let isCurrentlyPlaying = (p.timeControlStatus != .paused)
                let wasPlaying = self.isPlaying
                self.isPlaying = isCurrentlyPlaying
                
                // If the video is rendering frames or time is advancing, dismiss buffering popup
                if self.isBuffering && (secs > 0.05 || p.timeControlStatus == .playing || p.rate > 0 || current.status == .readyToPlay) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.isBuffering = false
                    }
                    self.scheduleControlsAutoHide()
                } else if !wasPlaying && isCurrentlyPlaying {
                    self.scheduleControlsAutoHide()
                }
                
                if !self.isScrubbingWithGesture && !self.isScrubbingTimeline && secs.isFinite && !secs.isNaN && dur.isFinite && !dur.isNaN && secs >= 2.0 {
                    VideoPlaybackStore.shared.savePosition(secs, duration: dur, for: item)
                }
            }
        }
    }
}
