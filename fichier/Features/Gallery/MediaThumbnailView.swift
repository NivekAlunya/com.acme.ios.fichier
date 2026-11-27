//
//  MediaThumbnailView.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Asynchronous thumbnail loading component rendering cached or remote previews for photos, videos, and documents.
///
/// ### Core Capabilities
/// - **Cooperative Task Lifecycle**: Spawns an asynchronous `@MainActor` task on `.onAppear` to fetch thumbnails
///   from `StorageLocationManager`, and automatically cancels outstanding tasks on `.onDisappear`.
/// - **Type Badges**: Renders overlay badges for videos (with live `VideoProgressRing` and watch status checkmarks),
///   animated GIFs, and PDF documents.
/// - **Progress Bar**: Renders a bottom progress bar for partially-watched videos using `.scaleEffect(x:...)`
///   to avoid infinite geometry expansion inside list rows.
/// - **Resilience**: Features automatic single retry after 1.5 seconds for video frame extraction failures,
///   and provides a manual tap-to-retry button upon permanent error.
public struct MediaThumbnailView: View {
    /// Shared storage location manager handling thumbnail caches and workers.
    public var manager: StorageLocationManager
    
    /// The media item whose thumbnail is rendered.
    public let item: MediaItem
    
    /// Target maximum pixel bounding box for downsampled image decoding.
    public var maxDimension: CGFloat = 260
    
    /// Corner radius applied to thumbnail clipping and placeholder styling.
    public var cornerRadius: CGFloat = 10
    
    /// Configures layout for compact environments such as table list cells.
    public var isCompact: Bool = false
    
    /// Configures whether overlay badges (format capsule, progress bar) are rendered internally.
    public var showsBadges: Bool = true
    
    /// Successfully loaded and decoded thumbnail image.
    @State private var image: UIImage?
    
    /// Unique identifier key tracked for item recycling and version updates.
    @State private var currentKey: String = ""
    
    /// Indicates whether thumbnail generation or download failed.
    @State private var loadFailed: Bool = false
    
    /// Retry attempt counter for transient network / streaming timeouts.
    @State private var retryCount: Int = 0
    
    /// Memberwise initializer for thumbnail configuration.
    ///
    /// - Parameters:
    ///   - manager: Shared storage location manager.
    ///   - item: Target media item.
    ///   - maxDimension: Maximum pixel bounding dimension (defaults to 260).
    ///   - cornerRadius: Clipping corner radius (defaults to 10).
    ///   - isCompact: Whether rendered in compact list mode (defaults to `false`).
    ///   - showsBadges: Whether overlay badges and progress bars are rendered internally (defaults to `true`).
    public init(
        manager: StorageLocationManager,
        item: MediaItem,
        maxDimension: CGFloat = 260,
        cornerRadius: CGFloat = 10,
        isCompact: Bool = false,
        showsBadges: Bool = true
    ) {
        self.manager = manager
        self.item = item
        self.maxDimension = maxDimension
        self.cornerRadius = cornerRadius
        self.isCompact = isCompact
        self.showsBadges = showsBadges
    }
    
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(AppColor.secondarySystemBackground)
            
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .transition(.opacity)
            } else if item.isPDF && !loadFailed {
                pdfPlaceholderView
            } else if loadFailed {
                failedPlaceholderView
            } else {
                if isCompact {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            
            if showsBadges {
                if item.isVideo {
                    let playbackStatus = VideoPlaybackStore.shared.status(for: item)
                    
                    // Progress bar along the bottom edge (using scaleEffect instead of GeometryReader to prevent container expansion in list cells)
                    if case .inProgress(let progress) = playbackStatus, progress > 0 {
                        let barHeight: CGFloat = isCompact ? 2.5 : 3.5
                        VStack(spacing: 0) {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Color.black.opacity(0.4)
                                
                                FichierTheme.accent
                                    .scaleEffect(x: max(0, min(1, CGFloat(progress))), y: 1, anchor: .leading)
                            }
                            .frame(height: barHeight)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .allowsHitTesting(false)
                    }
                    
                    let ext = (item.name as NSString).pathExtension
                    let formatLabel = VideoFormatStyle.label(for: ext)
                    let badgeColor = VideoFormatStyle.color(for: ext)
                    
                    // Video Playback Status & Format Capsule (Bottom-Trailing)
                    HStack(spacing: isCompact ? 2.5 : 3.5) {
                        Image(systemName: "video.fill")
                            .font(.system(size: isCompact ? 7 : 8))
                            .foregroundColor(.white)
                        
                        Text(formatLabel)
                            .font(.system(size: isCompact ? 7 : 8, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        switch playbackStatus {
                        case .finished:
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: isCompact ? 7 : 8, weight: .bold))
                                .foregroundColor(.green)
                        case .inProgress(let progress):
                            VideoProgressRing(
                                progress: progress,
                                size: isCompact ? 7.5 : 9.0,
                                lineWidth: isCompact ? 1.3 : 1.5,
                                ringColor: .white
                            )
                        case .unwatched:
                            EmptyView()
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, isCompact ? 4 : 6)
                    .padding(.vertical, isCompact ? 2 : 3)
                    .background(badgeColor.opacity(isCompact ? 0.88 : 0.85))
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
                    .padding(isCompact ? 2 : 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                } else if item.isGIF {
                    Text(.Strings.galleryBadgeGif)
                        .font(.system(size: isCompact ? 7 : 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, isCompact ? 3 : 5)
                        .padding(.vertical, isCompact ? 1 : 3)
                        .background(Color.black.opacity(isCompact ? 0.75 : 0.65))
                        .clipShape(Capsule())
                        .padding(isCompact ? 2 : 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                } else if item.isPDF && image != nil {
                    Text(.Strings.mediaBadgePdf)
                        .font(.system(size: isCompact ? 7 : 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, isCompact ? 3 : 5)
                        .padding(.vertical, isCompact ? 1 : 3)
                        .background(Color.red.opacity(isCompact ? 0.85 : 0.8))
                        .clipShape(Capsule())
                        .padding(isCompact ? 2 : 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: image != nil)
        .task(id: "\(item.id)-\(manager.thumbnailVersions[item.id] ?? 0)") {
            await loadThumbnail()
        }
    }
    
    // MARK: - Lightweight PDF Placeholder View
    
    /// Lightweight, zero-allocation vector document placeholder rendered natively in SwiftUI.
    @ViewBuilder
    private var pdfPlaceholderView: some View {
        if isCompact {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 20))
                .foregroundStyle(.red.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: maxDimension * 0.16))
                    .foregroundStyle(.red.gradient)
                    .shadow(color: .red.opacity(0.18), radius: 3, y: 2)
                
                Text(item.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                
                if !item.formattedSize.isEmpty && item.formattedSize != "…" {
                    Text(item.formattedSize)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .background(AppColor.tertiarySystemFill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
    
    // MARK: - Non-Blocking Failure Placeholder View
    
    /// Non-blocking failure placeholder allowing cell taps to pass through for video playback.
    @ViewBuilder
    private var failedPlaceholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.35))
            
            // Centered non-interactive placeholder graphic
            VStack(spacing: 6) {
                Image(systemName: item.isVideo ? "play.circle.fill" : (item.isPDF ? "doc.text.fill" : "photo"))
                    .font(.system(size: isCompact ? 20 : 28))
                    .foregroundColor(.white.opacity(0.8))
                
                if !isCompact {
                    Text(item.isVideo ? .Strings.galleryThumbnailPlayVideo : .Strings.galleryThumbnailRetryPreview)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    // MARK: - Loading Logic
    
    /// Asynchronously fetches or downloads the thumbnail from cache, updating image state cooperatively.
    private func loadThumbnail() async {
        let taskKey = "\(item.id)-\(manager.thumbnailVersions[item.id] ?? 0)"
        if currentKey != taskKey {
            if !currentKey.hasPrefix("\(item.id)-") {
                // Different media item (cell reuse): discard stale thumbnail immediately
                self.image = nil
            }
            self.currentKey = taskKey
            self.retryCount = 0
            self.loadFailed = false
        } else if image != nil {
            return
        }
        
        let loaded = await manager.downloadThumbnail(for: item, maxDimension: maxDimension)
        guard !Task.isCancelled else { return }

        if let loaded {
            withAnimation(.easeIn(duration: 0.2)) {
                self.image = loaded
                self.loadFailed = false
            }
        } else if item.isPDF {
            // Remote PDF without a cached thumbnail: display lightweight SwiftUI placeholder without error
            self.loadFailed = false
        } else if item.isVideo {
            if retryCount < 1 {
                retryCount += 1
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled && self.image == nil else { return }
                let retryLoaded = await manager.downloadThumbnail(for: item, maxDimension: maxDimension)
                guard !Task.isCancelled else { return }
                if let retryLoaded {
                    withAnimation(.easeIn(duration: 0.2)) {
                        self.image = retryLoaded
                        self.loadFailed = false
                    }
                } else {
                    withAnimation {
                        self.loadFailed = true
                    }
                }
            } else {
                withAnimation {
                    self.loadFailed = true
                }
            }
        } else {
            withAnimation {
                self.loadFailed = true
            }
        }
    }
}
