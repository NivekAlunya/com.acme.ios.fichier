//
//  VideoDetailView.swift
//  fichier
//

import SwiftUI
import AVKit
import Combine

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
    
    // Swipe to Seek Gesture State
    @State private var isScrubbingWithGesture: Bool = false
    @State private var scrubDeltaSeconds: Double = 0
    @State private var initialScrubTimeSeconds: Double = 0
    @State private var scrubTargetTimeSeconds: Double = 0
    @State private var videoDurationSeconds: Double = 0
    @State private var wasPlayingBeforeScrub: Bool = false
    @State private var scrubDismissTask: Task<Void, Never>?
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
            
            // Video Player or Instant Preview Thumbnail
            if let player {
                VideoPlayer(player: player)
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
                    Text("Buffering video from server...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
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
                    Button("Retry") {
                        setupPlayer(for: currentItem)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            
            // Overlay Controls
            if showControls {
                VStack {
                    topBar
                    Spacer()
                }
                .transition(.opacity)
                
                // Side Navigation Arrows (Vertically Centered - Avoids overlapping bottom player timeline)
                if videos.count > 1 {
                    HStack {
                        Button {
                            withAnimation { goToPrevious() }
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
                            withAnimation { goToNext() }
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 42))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                        }
                        .padding(.trailing, 18)
                    }
                    .transition(.opacity)
                }
            }
            
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
            
            // Swipe to Seek HUD Indicator
            if isScrubbingWithGesture {
                seekHUDOverlay
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .contentShape(Rectangle())
        .simultaneousGesture(videoSeekGesture)
        .onTapGesture {
            guard !isScrubbingWithGesture else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls.toggle()
            }
        }
        .task(id: currentItem.id) {
            setupPlayer(for: currentItem)
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard !isScrubbingWithGesture else { return }
            guard let item = notification.object as? AVPlayerItem,
                  let current = player?.currentItem,
                  item == current else { return }
            playNextVideo()
        }
        .onDisappear {
            tearDownPlayer()
        }
    }
    
    // Floating Centered Top HUD Capsule (Safely avoids top-left PiP and top-right AirPlay)
    private var topBar: some View {
        HStack {
            Spacer()
            
            HStack(spacing: 10) {
                // 1. Close Button (Centered capsule avoids top-left PiP button!)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Circle())
                }
                
                Divider()
                    .frame(height: 18)
                    .background(Color.white.opacity(0.3))
                
                // 2. Previous Video
                if videos.count > 1 {
                    Button {
                        withAnimation { goToPrevious() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                    }
                }
                
                // 3. Title & Counter
                VStack(spacing: 1) {
                    Text(currentItem.name)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: 140)
                    
                    Text("\(currentIndex + 1) of \(videos.count) • \(currentItem.formattedSize)")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // 4. Next Video
                if videos.count > 1 {
                    Button {
                        withAnimation { goToNext() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                    }
                }
                
                Divider()
                    .frame(height: 18)
                    .background(Color.white.opacity(0.3))
                
                // 5. Favorite Button
                Button {
                    FavoritesManager.shared.toggleFavorite(currentItem)
                } label: {
                    Image(systemName: FavoritesManager.shared.isFavorite(currentItem) ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundStyle(FavoritesManager.shared.isFavorite(currentItem) ? Color.red : Color.white)
                        .padding(5)
                }
                
                // 6. Save to Camera Roll
                Button {
                    saveToCameraRoll()
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .padding(5)
                    }
                }
                .disabled(isSaving)
                
                // 7. ShareLink
                if MediaCacheManager.shared.hasCachedVideo(for: currentItem) {
                    ShareLink(
                        item: MediaCacheManager.shared.localVideoURL(for: currentItem),
                        preview: SharePreview(currentItem.name)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .padding(5)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            )
            
            Spacer()
        }
        .padding(.top, 10)
    }
    
    private func goToNext() {
        guard !videos.isEmpty else { return }
        let nextIndex = (currentIndex + 1) % videos.count
        currentItem = videos[nextIndex]
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
        currentItem = videos[prevIndex]
    }
    
    private func saveToCameraRoll() {
        isSaving = true
        Task {
            do {
                let localURL = try await manager.fetchVideoURL(for: currentItem)
                try await PhotoLibrarySaver.saveVideoToPhotos(at: localURL)
                withAnimation {
                    saveStatusMessage = "Video Saved to Photos"
                }
            } catch {
                withAnimation {
                    saveStatusMessage = "Failed to save: \(error.localizedDescription)"
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
        scrubDismissTask?.cancel()
        scrubDismissTask = nil
        isScrubbingWithGesture = false
        scrubDeltaSeconds = 0
        isSeekingFrame = false
        pendingSeekSeconds = nil
        loadTask?.cancel()
        loadTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        loaderDelegate?.cancelAll()
        loaderDelegate = nil
        player?.pause()
        player = nil
        isBuffering = true
        errorMessage = nil
    }
    
    // MARK: - Swipe to Seek (Backward / Forward)
    
    private var seekHUDOverlay: some View {
        VStack(spacing: 8) {
            // Direction Icon & Time Offset
            HStack(spacing: 8) {
                Image(systemName: scrubDeltaSeconds >= 0 ? "goforward" : "gobackward")
                    .font(.system(size: 26, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                
                Text(formatDeltaSeconds(scrubDeltaSeconds))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            
            // Target Timestamp & Total Duration
            HStack(spacing: 4) {
                Text(formatSeconds(scrubTargetTimeSeconds))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                
                if videoDurationSeconds > 0 {
                    Text("/ \(formatSeconds(videoDurationSeconds))")
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.65))
                }
            }
            
            // Mini Progress Bar
            if videoDurationSeconds > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.25))
                            .frame(height: 4)
                        
                        let progress = max(0.0, min(1.0, scrubTargetTimeSeconds / videoDurationSeconds))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * CGFloat(progress), height: 4)
                    }
                }
                .frame(width: 130, height: 4)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
        )
        .transition(.scale(scale: 0.88).combined(with: .opacity))
    }
    
    private var videoSeekGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                let hTranslation = value.translation.width
                let vTranslation = value.translation.height
                
                // Only handle horizontal swipes
                guard abs(hTranslation) > abs(vTranslation) else { return }
                guard let player = player else { return }
                
                scrubDismissTask?.cancel()
                scrubDismissTask = nil
                
                if !isScrubbingWithGesture {
                    isScrubbingWithGesture = true
                    wasPlayingBeforeScrub = (player.timeControlStatus == .playing)
                    if wasPlayingBeforeScrub {
                        player.pause()
                    }
                    
                    let current = player.currentTime().seconds
                    initialScrubTimeSeconds = (current.isFinite && !current.isNaN) ? max(0, current) : 0
                    
                    let dur = player.currentItem?.duration.seconds ?? 0
                    videoDurationSeconds = (dur.isFinite && !dur.isNaN && dur > 0) ? dur : 0
                }
                
                // Scaled sensitivity based on video length
                let sensitivity: Double
                if videoDurationSeconds > 3600 {
                    sensitivity = 2.0   // Movies (> 1 hr): ~10 min for a full swipe
                } else if videoDurationSeconds > 600 {
                    sensitivity = 1.0   // Medium videos (10-60 min): ~5 min for a full swipe
                } else {
                    sensitivity = 0.75  // Short clips (< 10 min): 30s per 40pt
                }
                
                let rawDelta = Double(hTranslation) * sensitivity
                scrubDeltaSeconds = round(rawDelta)
                
                let target = initialScrubTimeSeconds + scrubDeltaSeconds
                if videoDurationSeconds > 0 {
                    scrubTargetTimeSeconds = max(0, min(videoDurationSeconds, target))
                } else {
                    scrubTargetTimeSeconds = max(0, target)
                }
                
                // Live frame rendering while sliding/swiping
                requestLiveFrameSeek(to: scrubTargetTimeSeconds)
            }
            .onEnded { value in
                guard isScrubbingWithGesture else { return }
                guard let player = player else {
                    isScrubbingWithGesture = false
                    return
                }
                
                pendingSeekSeconds = nil
                isSeekingFrame = false
                
                let hTranslation = value.translation.width
                let vTranslation = value.translation.height
                
                if abs(hTranslation) > abs(vTranslation) && abs(hTranslation) >= 15 {
                    var finalDelta = scrubDeltaSeconds
                    
                    // Large minimum step on quick flick / swipe: at least 30s
                    let minFlickStep: Double = (videoDurationSeconds > 0 && videoDurationSeconds < 60) ? 10.0 : 30.0
                    let predictedH = value.predictedEndTranslation.width
                    if abs(hTranslation) < 60 && abs(predictedH) >= 80 {
                        finalDelta = predictedH > 0 ? max(minFlickStep, scrubDeltaSeconds) : min(-minFlickStep, scrubDeltaSeconds)
                        scrubDeltaSeconds = finalDelta
                        let target = initialScrubTimeSeconds + finalDelta
                        if videoDurationSeconds > 0 {
                            scrubTargetTimeSeconds = max(0, min(videoDurationSeconds, target))
                        } else {
                            scrubTargetTimeSeconds = max(0, target)
                        }
                    }
                    
                    let targetCM = CMTime(seconds: scrubTargetTimeSeconds, preferredTimescale: 600)
                    player.seek(to: targetCM, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        Task { @MainActor in
                            if wasPlayingBeforeScrub {
                                player.play()
                            }
                        }
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } else {
                    let targetCM = CMTime(seconds: scrubTargetTimeSeconds, preferredTimescale: 600)
                    player.seek(to: targetCM, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        Task { @MainActor in
                            if wasPlayingBeforeScrub {
                                player.play()
                            }
                        }
                    }
                }
                
                // Keep HUD visible briefly to confirm seek position, then fade out
                scrubDismissTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        isScrubbingWithGesture = false
                        scrubDeltaSeconds = 0
                    }
                }
            }
    }
    
    // MARK: - Live Frame Seeking During Gesture
    
    private func requestLiveFrameSeek(to targetSeconds: Double) {
        guard let player = player else { return }
        
        // If an async seek is currently in flight, record this as the pending target
        guard !isSeekingFrame else {
            pendingSeekSeconds = targetSeconds
            return
        }
        
        // Throttle slightly (at least 60ms between calls) to prevent flooding decoder / network
        let now = Date()
        if now.timeIntervalSince(lastSeekTime) < 0.06 {
            pendingSeekSeconds = targetSeconds
            return
        }
        
        isSeekingFrame = true
        lastSeekTime = now
        
        let targetCM = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        // Keyframe tolerance during interactive scrubbing for instant visual frame response
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
    
    private func formatDeltaSeconds(_ delta: Double) -> String {
        let sign = delta >= 0 ? "+" : "-"
        let absSecs = Int(abs(delta))
        if absSecs >= 3600 {
            let hours = absSecs / 3600
            let mins = (absSecs % 3600) / 60
            let secs = absSecs % 60
            return String(format: "%@%dh %02dm %02ds", sign, hours, mins, secs)
        } else if absSecs >= 60 {
            let mins = absSecs / 60
            let secs = absSecs % 60
            if secs == 0 {
                return "\(sign)\(mins)m"
            } else {
                return String(format: "%@%dm %02ds", sign, mins, secs)
            }
        } else {
            return "\(sign)\(absSecs)s"
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
            avPlayer.play()
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
                self.errorMessage = "Invalid video stream URL"
                self.isBuffering = false
                return
            }
            
            let asset = AVURLAsset(url: streamURL)
            let delegate = SMBResourceLoaderDelegate(manager: self.manager, item: validItem)
            self.loaderDelegate = delegate
            
            let queue = DispatchQueue(label: "com.acme.ios.photos.videoloader.\(uniqueID)", qos: .userInitiated)
            asset.resourceLoader.setDelegate(delegate, queue: queue)
            
            let playerItem = AVPlayerItem(asset: asset)
            let avPlayer = AVPlayer(playerItem: playerItem)
            avPlayer.automaticallyWaitsToMinimizeStalling = true
            self.player = avPlayer
            avPlayer.play()
            
            // Monitor playback readiness
            self.monitorTask?.cancel()
            self.monitorTask = Task { @MainActor [weak avPlayer] in
                while !Task.isCancelled {
                    guard let p = avPlayer else { break }
                    if p.timeControlStatus == .playing {
                        self.isBuffering = false
                        break
                    }
                    if let err = p.currentItem?.error {
                        self.errorMessage = "Playback error: \(err.localizedDescription)"
                        self.isBuffering = false
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
        }
    }
}
