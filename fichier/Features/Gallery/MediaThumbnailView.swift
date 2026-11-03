//
//  MediaThumbnailView.swift
//  fichier
//

import SwiftUI

public struct MediaThumbnailView: View {
    public var manager: SMBDirectManager
    public let item: MediaItem
    public var maxDimension: CGFloat = 260
    public var cornerRadius: CGFloat = 10
    public var isCompact: Bool = false
    
    @State private var image: UIImage?
    @State private var loadTask: Task<Void, Never>?
    @State private var loadFailed: Bool = false
    @State private var retryCount: Int = 0
    
    public init(
        manager: SMBDirectManager,
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
            } else if item.isPDF {
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
    }
    
    // MARK: - Loading & Retry Logic
    
    private func startLoading() {
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
    
    private func retryLoading() {
        retryCount = 0
        startLoading()
    }
    
    private func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
    }
}
