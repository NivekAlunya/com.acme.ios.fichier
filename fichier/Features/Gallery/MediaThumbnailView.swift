//
//  MediaThumbnailView.swift
//  fichier
//

import SwiftUI

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
    
    /// Successfully loaded and decoded thumbnail image.
    @State private var image: UIImage?
    
    /// In-flight asynchronous thumbnail loading task.
    @State private var loadTask: Task<Void, Never>?
    
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
    public init(
        manager: StorageLocationManager,
        item: MediaItem,
        maxDimension: CGFloat = 260,
        cornerRadius: CGFloat = 10,
        isCompact: Bool = false
    ) {
        self.manager = manager
        self.item = item
        self.maxDimension = maxDimension
        self.cornerRadius = cornerRadius
        self.isCompact = isCompact
    }
    
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.secondarySystemBackground))
            
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else if item.isPDF && !loadFailed {
                pdfPlaceholderView
            } else if loadFailed {
                Button {
                    retryLoading()
                } label: {
                    if isCompact {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white.opacity(0.85))
                            Text(.Strings.galleryThumbnailRetryPreview)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .background(Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    }
                }
                .buttonStyle(.plain)
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
            
            if item.isVideo {
                let playbackStatus = VideoPlaybackStore.shared.status(for: item)
                
                // Progress bar along the bottom edge (using scaleEffect instead of GeometryReader to prevent container expansion in list cells)
                if case .inProgress(let progress) = playbackStatus, progress > 0 {
                    let barHeight: CGFloat = isCompact ? 2.5 : 3.5
                    VStack(spacing: 0) {
                        Spacer()
                        ZStack(alignment: .leading) {
                            Color.black.opacity(0.4)
                            
                            Color.blue
                                .scaleEffect(x: max(0, min(1, CGFloat(progress))), y: 1, anchor: .leading)
                        }
                        .frame(height: barHeight)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .allowsHitTesting(false)
                }
                
                // Video Playback Status Badge (Bottom-Trailing)
                HStack(spacing: isCompact ? 3 : 4) {
                    Image(systemName: "video.fill")
                        .font(.system(size: isCompact ? 8 : 9))
                        .foregroundColor(.white)
                    
                    if !isCompact {
                        Text(.Strings.galleryBadgeVideo)
                            .font(.system(size: 8, weight: .bold))
                    }
                    
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
                            ringColor: .blue
                        )
                    case .unwatched:
                        EmptyView()
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, isCompact ? 4 : 5)
                .padding(.vertical, isCompact ? 2 : 3)
                .background(Color.black.opacity(isCompact ? 0.75 : 0.65))
                .clipShape(Capsule())
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
                Text("PDF")
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
        .onAppear {
            if image == nil {
                startLoading()
            }
        }
        .onDisappear {
            cancelLoading()
        }
        .onChange(of: manager.thumbnailVersions[item.id]) { _, _ in
            startLoading(force: true)
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
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
    
    // MARK: - Loading & Retry Logic
    
    /// Spawns an asynchronous task to download or retrieve the thumbnail from cache.
    ///
    /// - Parameter force: When `true`, overrides currently displayed image to fetch freshly upgraded thumbnails.
    private func startLoading(force: Bool = false) {
        if !force && image != nil { return }
        loadTask?.cancel()
        loadFailed = false
        
        loadTask = Task { @MainActor in
            if Task.isCancelled { return }
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
                    startLoading()
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
    
    /// Resets the retry counter and reinitiates thumbnail loading.
    private func retryLoading() {
        retryCount = 0
        startLoading(force: true)
    }
    
    /// Cancels in-flight loading tasks and clears references.
    private func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
    }
}
