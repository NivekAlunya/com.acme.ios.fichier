//
//  VideoDetailView.swift
//  fichier
//

import SwiftUI
import AVKit
import OSLog

public struct VideoDetailView: View {
    var manager: SMBDirectManager
    let videos: [MediaItem]
    let initialItem: MediaItem
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var currentItem: MediaItem
    @State private var currentlyLoadedItem: MediaItem?
    @State private var playbackStartTime: Date = Date()
    @State private var didRestorePlaybackPosition: Bool = false
    @State private var restoredFromSeconds: Double? = nil
    @State private var player: AVPlayer?
    @State private var currentAsset: AVURLAsset?
    @State private var loaderDelegate: SMBResourceLoaderDelegate?
    @State private var isBuffering = true
    @State private var errorMessage: String?
    @State private var showControls: Bool = true
    @State private var isSaving: Bool = false
    @State private var saveStatusMessage: String?
    @State private var monitorTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?
    @State private var shareableVideoURL: URL?
    
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
    @State private var lastSeekTargetSeconds: Double = 0
    @State private var seekGeneration: Int = 0
    @State private var stationarySeekTask: Task<Void, Never>?
    @State private var throttleSeekTask: Task<Void, Never>?
    @State private var seekWatchdogTask: Task<Void, Never>?
    
    public init(
        manager: SMBDirectManager,
        videos: [MediaItem],
        initialItem: MediaItem
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
                    .accessibilityLabel(String(localized: "Retry Loading Video", comment: "Accessibility label to retry loading video"))
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
                    .accessibilityLabel(isPlaying ? String(localized: "Pause", comment: "Accessibility label to pause playback") : String(localized: "Play", comment: "Accessibility label to start playback"))
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
                        .accessibilityLabel(String(localized: "Previous Video", comment: "Accessibility label for previous video"))
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
                        .accessibilityLabel(String(localized: "Next Video", comment: "Accessibility label for next video"))
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
            
            // If the video reached end-of-play immediately after restoring a saved position near the end,
            // rewind to 0:00 so the user can watch the full video from the beginning.
            // Short videos (duration <= 3.0s) or videos that played normally should not be looped.
            if didRestorePlaybackPosition && (totalDurationSeconds > 3.0 || totalDurationSeconds == 0) {
                didRestorePlaybackPosition = false
                restoredFromSeconds = nil
                player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                currentPlaybackSeconds = 0
                VideoPlaybackStore.shared.clearPosition(for: targetItem)
                player?.play()
                isPlaying = true
                return
            }
            
            didRestorePlaybackPosition = false
            restoredFromSeconds = nil
            
            if totalDurationSeconds >= 2.0 && currentPlaybackSeconds >= totalDurationSeconds * 0.9 {
                VideoPlaybackStore.shared.markFinished(for: targetItem, duration: totalDurationSeconds)
            }
            playNextVideo()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification)) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  let current = player?.currentItem,
                  item == current else { return }
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                self.errorMessage = String(localized: .Strings.videoPlayerErrorPlayback(error.localizedDescription))
                self.isBuffering = false
            }
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
            guard !isPiPActive else { return }
            tearDownPlayer(deactivateAudioSession: true)
        }
        .background {
            // Hardware Keyboard Shortcuts for iPad and Mac
            Group {
                Button("") {
                    tearDownPlayer(deactivateAudioSession: true)
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Button("") { togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                
                Button("") { togglePlayPause() }
                    .keyboardShortcut("k", modifiers: [])
                
                Button("") { seekRelative(-5) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                
                Button("") { seekRelative(5) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                
                Button("") { seekRelative(-10) }
                    .keyboardShortcut("j", modifiers: [])
                
                Button("") { seekRelative(10) }
                    .keyboardShortcut("l", modifiers: [])
                
                Button("") { goToPrevious() }
                    .keyboardShortcut("[", modifiers: [])
                
                Button("") { goToNext() }
                    .keyboardShortcut("]", modifiers: [])
                
                Button("") { toggleMute() }
                    .keyboardShortcut("m", modifiers: [])
                
                Button("") { adjustVolume(by: 0.1) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                
                Button("") { adjustVolume(by: -0.1) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                
                Button("") { FavoritesManager.shared.toggleFavorite(currentItem) }
                    .keyboardShortcut("f", modifiers: [])
            }
            .opacity(0)
            .allowsHitTesting(false)
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
            tearDownPlayer(deactivateAudioSession: true)
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
        .accessibilityLabel(String(localized: "Close", comment: "Accessibility label to close video player"))
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
    
    private var titleTextContent: some View {
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
    }
    
    private var titleCapsule: some View {
        titleTextContent
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
        .accessibilityLabel(String(localized: "Previous Video", comment: "Accessibility label for previous video"))
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
        .accessibilityLabel(String(localized: "Next Video", comment: "Accessibility label for next video"))
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
        .accessibilityLabel(String(localized: "Playback Options", comment: "Accessibility label for playback options menu"))
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
            .accessibilityLabel(FavoritesManager.shared.isFavorite(currentItem) ? String(localized: "Remove from Favorites", comment: "Accessibility label to unfavorite") : String(localized: "Add to Favorites", comment: "Accessibility label to favorite"))
            
            if !currentItem.isPhotoAsset {
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
                .accessibilityLabel(String(localized: "Save to Photos", comment: "Accessibility label to save video to Photos"))
            }
            
            // 3. ShareLink
            if let shareableVideoURL {
                ShareLink(
                    item: shareableVideoURL,
                    preview: SharePreview(currentItem.name)
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Share Video", comment: "Accessibility label to share video"))
            }
            
            // 4. AirPlay Button
            AirPlayButtonView()
                .frame(width: 30, height: 30)
                .accessibilityLabel(String(localized: "AirPlay", comment: "Accessibility label for AirPlay"))
            
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
            .accessibilityLabel(String(localized: "Restart from beginning", comment: "Accessibility label to restart playback from start"))
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
                titleTextContent
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
                    lastSeekTargetSeconds = currentPlaybackSeconds
                    wasPlayingBeforeScrub = (player?.timeControlStatus != .paused)
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
                guard let player = player else { return }
                
                if !isScrubbingWithGesture {
                    guard abs(hTranslation) > abs(vTranslation) else { return }
                    isScrubbingWithGesture = true
                    hideControlsTask?.cancel()
                    lastSeekTargetSeconds = currentPlaybackSeconds
                    wasPlayingBeforeScrub = (player.timeControlStatus != .paused)
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
                let maxTarget = (totalDurationSeconds.isFinite && !totalDurationSeconds.isNaN && totalDurationSeconds > 0) ? totalDurationSeconds : Double.greatestFiniteMagnitude
                let target = max(0, min(maxTarget, initialScrubTime + delta))
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
    
    private func liveSeekTolerance(for targetSeconds: Double) -> CMTime {
        let delta = abs(targetSeconds - lastSeekTargetSeconds)
        if delta < 0.75 {
            return CMTime(seconds: 0.04, preferredTimescale: 600)
        } else if delta < 3.0 {
            return CMTime(seconds: 0.35, preferredTimescale: 600)
        } else if delta < 10.0 {
            return CMTime(seconds: 1.5, preferredTimescale: 600)
        } else {
            return .positiveInfinity
        }
    }
    
    private func requestLiveFrameSeek(to targetSeconds: Double) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSeekTime)
        
        // 1. Reset stationary debounce timer on any movement.
        // When the user stops moving their finger (holding stationary without lifting),
        // after 120ms this task triggers an exact zero-tolerance seek to display the exact frame.
        stationarySeekTask?.cancel()
        stationarySeekTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            performStationaryExactSeek(to: targetSeconds)
        }
        
        // 2. If a seek is in flight, buffer the latest target unless the in-flight seek is stale (>= 85ms),
        // in which case we preempt the stale seek immediately so fast scrubbing samples more frames.
        if isSeekingFrame && elapsed < 0.085 {
            pendingSeekSeconds = targetSeconds
            return
        }
        
        // 3. Pace live intermediate seeks at ~60fps (16ms) to sample maximum frames without flooding AVPlayer
        let minInterval: TimeInterval = 0.016
        
        if elapsed < minInterval {
            pendingSeekSeconds = targetSeconds
            if throttleSeekTask == nil {
                let remaining = max(0.005, minInterval - elapsed)
                throttleSeekTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
                    guard !Task.isCancelled else { return }
                    self.throttleSeekTask = nil
                    if let next = self.pendingSeekSeconds {
                        self.pendingSeekSeconds = nil
                        self.executeLiveSeek(to: next, tolerance: self.liveSeekTolerance(for: next))
                    }
                }
            }
            return
        }
        
        // 4. Dispatch live seek with adaptive tolerance for high-rate visual feedback while moving
        executeLiveSeek(to: targetSeconds, tolerance: liveSeekTolerance(for: targetSeconds))
    }
    
    private func executeLiveSeek(to targetSeconds: Double, tolerance: CMTime) {
        guard let player = player else { return }
        throttleSeekTask?.cancel()
        throttleSeekTask = nil
        seekWatchdogTask?.cancel()
        seekWatchdogTask = nil
        didRestorePlaybackPosition = false
        restoredFromSeconds = nil
        
        seekGeneration += 1
        let thisGeneration = seekGeneration
        isSeekingFrame = true
        lastSeekTime = Date()
        lastSeekTargetSeconds = targetSeconds
        
        let targetCM = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: targetCM, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in
            Task { @MainActor in
                guard thisGeneration == self.seekGeneration else { return }
                self.isSeekingFrame = false
                if let nextTarget = self.pendingSeekSeconds {
                    self.pendingSeekSeconds = nil
                    self.executeLiveSeek(to: nextTarget, tolerance: self.liveSeekTolerance(for: nextTarget))
                }
            }
        }
    }
    
    private func performStationaryExactSeek(to targetSeconds: Double) {
        guard let player = player else { return }
        
        // Finger has stopped moving! Cancel any throttled intermediate seeks.
        throttleSeekTask?.cancel()
        throttleSeekTask = nil
        seekWatchdogTask?.cancel()
        seekWatchdogTask = nil
        pendingSeekSeconds = nil
        
        seekGeneration += 1
        let thisGeneration = seekGeneration
        isSeekingFrame = true
        lastSeekTime = Date()
        lastSeekTargetSeconds = targetSeconds
        
        let targetCM = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: targetCM, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                guard thisGeneration == self.seekGeneration else { return }
                self.isSeekingFrame = false
                if let nextTarget = self.pendingSeekSeconds {
                    self.pendingSeekSeconds = nil
                    self.executeLiveSeek(to: nextTarget, tolerance: self.liveSeekTolerance(for: nextTarget))
                }
            }
        }
    }
    
    private func finishSeeking(at targetSeconds: Double, resumePlaying: Bool) {
        stationarySeekTask?.cancel()
        stationarySeekTask = nil
        throttleSeekTask?.cancel()
        throttleSeekTask = nil
        pendingSeekSeconds = nil
        isSeekingFrame = false
        seekWatchdogTask?.cancel()
        seekWatchdogTask = nil
        didRestorePlaybackPosition = false
        restoredFromSeconds = nil
        
        seekGeneration += 1
        let thisGeneration = seekGeneration
        
        guard let player = player else { return }
        let targetCM = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        currentPlaybackSeconds = targetSeconds
        
        // Use 0.2s tolerance for seamless playback continuation, or .zero for stationary frame inspection
        let tolerance: CMTime = resumePlaying ? CMTime(seconds: 0.2, preferredTimescale: 600) : .zero
        
        // Fail-safe watchdog: ensure buffering indicator and playback state recover within 800ms
        seekWatchdogTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, thisGeneration == self.seekGeneration else { return }
            if self.isBuffering {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.isBuffering = false
                }
            }
            if resumePlaying && player.timeControlStatus != .playing {
                player.play()
                self.isPlaying = true
                self.scheduleControlsAutoHide()
            }
        }
        
        player.seek(to: targetCM, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in
            Task { @MainActor in
                guard thisGeneration == self.seekGeneration else { return }
                self.seekWatchdogTask?.cancel()
                self.seekWatchdogTask = nil
                
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.isBuffering = false
                }
                
                if resumePlaying {
                    player.play()
                    self.isPlaying = true
                }
                self.scheduleControlsAutoHide()
            }
        }
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
        if player.timeControlStatus != .paused {
            player.pause()
            isPlaying = false
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
                isPlaying = true
                scheduleControlsAutoHide()
            }
        }
    }
    
    private func seekTo(_ targetSeconds: Double, resumePlaying: Bool = false) {
        finishSeeking(at: targetSeconds, resumePlaying: resumePlaying)
    }
    
    private func seekRelative(_ deltaSeconds: Double) {
        let current = currentPlaybackSeconds
        let dur = totalDurationSeconds > 0 ? totalDurationSeconds : (player?.currentItem?.duration.seconds ?? 0)
        let maxLimit = dur > 0 ? dur : max(current + deltaSeconds, 0)
        let newTarget = min(max(0, current + deltaSeconds), maxLimit)
        seekTo(newTarget, resumePlaying: isPlaying)
        withAnimation {
            showControls = true
        }
        scheduleControlsAutoHide()
    }
    
    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        withAnimation {
            showControls = true
        }
        scheduleControlsAutoHide()
    }
    
    private func adjustVolume(by delta: Double) {
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
    
    private func tearDownPlayer(deactivateAudioSession: Bool = false) {
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
        stationarySeekTask?.cancel()
        stationarySeekTask = nil
        throttleSeekTask?.cancel()
        throttleSeekTask = nil
        seekWatchdogTask?.cancel()
        seekWatchdogTask = nil
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
        isScrubbingWithGesture = false
        isScrubbingTimeline = false
        isSeekingFrame = false
        pendingSeekSeconds = nil
        seekGeneration += 1
        player?.pause()
        player = nil
        isBuffering = true
        errorMessage = nil
        
        if deactivateAudioSession {
            Task.detached(priority: .utility) {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }
    
    private func restartVideo() {
        guard player != nil else { return }
        let targetItem = currentlyLoadedItem ?? currentItem
        didRestorePlaybackPosition = false
        restoredFromSeconds = nil
        resumeBannerTask?.cancel()
        seekTo(0, resumePlaying: isPlaying)
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
    
    private func setupPlayer(for item: MediaItem) {
        playbackStartTime = Date()
        didRestorePlaybackPosition = false
        restoredFromSeconds = nil
        tearDownPlayer(deactivateAudioSession: false)
        currentlyLoadedItem = item
        showControls = true
        
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
        
        // 1. If local file or previously downloaded/cached locally, play immediately from file
        if let localURL = item.localURL ?? (MediaCacheManager.shared.hasCachedVideo(for: item) ? MediaCacheManager.shared.localVideoURL(for: item) : nil) {
            self.shareableVideoURL = localURL
            let avPlayer = AVPlayer(url: localURL)
            self.player = avPlayer
            self.isBuffering = false
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
                    self.isBuffering = false
                    configurePlayer(avPlayer, for: item, loadTracksImmediately: true)
                    avPlayer.play()
                    self.scheduleControlsAutoHide()
                    startContinuousPlaybackMonitoring(for: avPlayer)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.errorMessage = String(localized: .Strings.videoPlayerErrorPlayback(error.localizedDescription))
                    self.isBuffering = false
                }
                return
            }
            
            let validItem = await manager.resolveValidItem(for: item)
            guard !Task.isCancelled else { return }
            
            guard validItem.size > 0, let (streamURL, uniqueID) = SMBDirectManager.makeStreamURL(for: validItem.name) else {
                self.errorMessage = String(localized: .Strings.videoPlayerErrorInvalidStreamUrl)
                self.isBuffering = false
                return
            }
            
            let asset = AVURLAsset(url: streamURL)
            self.currentAsset = asset
            let delegate = SMBResourceLoaderDelegate(worker: self.manager.clientActor, item: validItem)
            self.loaderDelegate = delegate
            
            let queue = DispatchQueue(label: "com.acme.ios.photos.videoloader.\(uniqueID)", qos: .userInitiated)
            asset.resourceLoader.setDelegate(delegate, queue: queue)
            
            let playerItem = AVPlayerItem(asset: asset)
            let avPlayer = AVPlayer(playerItem: playerItem)
            avPlayer.automaticallyWaitsToMinimizeStalling = true
            self.player = avPlayer
            configurePlayer(avPlayer, for: validItem, loadTracksImmediately: false)
            avPlayer.play()
            startContinuousPlaybackMonitoring(for: avPlayer)
        }
    }
    
    private func startContinuousPlaybackMonitoring(for avPlayer: AVPlayer) {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor [weak avPlayer] in
            var tracksLoaded = false
            var waitingStartTime: Date? = nil
            
            while !Task.isCancelled {
                guard let p = avPlayer else { break }
                let currentItem = p.currentItem
                
                // 1. Terminal error check
                let playbackError = p.error ?? currentItem?.error
                if playbackError != nil || p.status == .failed || currentItem?.status == .failed {
                    let desc = playbackError?.localizedDescription ?? "Playback error"
                    self.errorMessage = String(localized: .Strings.videoPlayerErrorPlayback(desc))
                    if self.isBuffering {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.isBuffering = false
                        }
                    }
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
                    if self.isBuffering {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.isBuffering = false
                        }
                    }
                    if !self.isPlaying {
                        self.isPlaying = true
                        self.scheduleControlsAutoHide()
                    }
                    
                case .paused:
                    waitingStartTime = nil
                    if self.isBuffering {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.isBuffering = false
                        }
                    }
                    if self.isPlaying && !self.isScrubbingTimeline && !self.isScrubbingWithGesture {
                        self.isPlaying = false
                    }
                    
                case .waitingToPlayAtSpecifiedRate:
                    if waitingStartTime == nil {
                        waitingStartTime = Date()
                    } else if let start = waitingStartTime, Date().timeIntervalSince(start) > 0.35 {
                        if !self.isBuffering && !self.isScrubbingTimeline && !self.isScrubbingWithGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.isBuffering = true
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
    
    private func configurePlayer(_ avPlayer: AVPlayer, for item: MediaItem, loadTracksImmediately: Bool) {
        // Sync volume & mute state
        self.volume = Double(avPlayer.volume)
        self.isMuted = avPlayer.isMuted
        self.isPlaying = true
        
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
        
        // 3. Load media tracks (audio / subtitles) immediately for local files
        if loadTracksImmediately, let currentItem = avPlayer.currentItem {
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
                
                // If playback advanced naturally past 2.5s from the restored point, clear restore flag
                if self.didRestorePlaybackPosition, let restored = self.restoredFromSeconds {
                    if abs(secs - restored) > 2.5 {
                        self.didRestorePlaybackPosition = false
                        self.restoredFromSeconds = nil
                    }
                }
                let isCurrentlyPlaying = (p.timeControlStatus != .paused)
                let wasPlaying = self.isPlaying
                self.isPlaying = isCurrentlyPlaying
                
                // If the video is rendering frames or time is advancing, dismiss buffering popup
                if self.isBuffering && (p.timeControlStatus == .playing || p.rate > 0 || current.isPlaybackLikelyToKeepUp) {
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
