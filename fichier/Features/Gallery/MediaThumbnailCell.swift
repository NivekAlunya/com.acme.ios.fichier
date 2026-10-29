//
//  MediaThumbnailCell.swift
//  fichier
//

import SwiftUI

struct MediaThumbnailCell: View {
    var manager: SMBDirectManager
    let item: SMBItem
    var maxDimension: CGFloat = 260
    var isSelected: Bool = false
    var isSelectionMode: Bool = false
    
    @State private var image: UIImage?
    @State private var loadTask: Task<Void, Never>?
    @State private var loadFailed: Bool = false
    @State private var retryCount: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Color(.secondarySystemBackground)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if loadFailed {
                    // Empty / failed video preview state: tap to retry
                    Button {
                        retryLoading()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white.opacity(0.85))
                            Text(.Strings.galleryThumbnailRetryPreview)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                
                if item.isVideo {
                    HStack(spacing: 3) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9))
                        Text(.Strings.galleryBadgeVideo)
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                } else if item.isGIF {
                    Text(.Strings.galleryBadgeGif)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                
                if isSelectionMode {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.blue : Color.black.opacity(0.4))
                            .frame(width: 24, height: 24)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: isSelected ? 0 : 1.5)
                    )
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.scale.combined(with: .opacity))
                } else if FavoritesManager.shared.isFavorite(item) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .padding(5)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
            )
            
            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(item.formattedSize)
                if let d = item.formattedDate {
                    Text("•")
                    Text(d)
                }
            }
            .font(.system(size: 9))
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        .onAppear {
            if image == nil {
                startLoading()
            }
        }
        .onDisappear {
            // Cancel preview/thumbnailing immediately when cell scrolls out of view
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
                // If a video preview wasn't fetched, retry once automatically after 1.5s while visible
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
