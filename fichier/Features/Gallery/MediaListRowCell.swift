//
//  MediaListRowCell.swift
//  fichier
//

import SwiftUI

struct MediaListRowCell: View {
    var manager: SMBDirectManager
    let item: SMBItem
    var isSelected: Bool = false
    var isSelectionMode: Bool = false
    
    @State private var thumbnail: UIImage?
    @State private var loadTask: Task<Void, Never>?
    @State private var loadFailed: Bool = false
    @State private var retryCount: Int = 0
    
    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.clear)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.6), lineWidth: 1.5)
                )
                .transition(.scale.combined(with: .opacity))
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 52, height: 52)
                
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if loadFailed {
                    Button {
                        retryLoading()
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 52, height: 52, alignment: .center)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 52, height: 52, alignment: .center)
                }
                
                if item.isVideo {
                    let playbackStatus = VideoPlaybackStore.shared.status(for: item)
                    
                    switch playbackStatus {
                    case .finished:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                            .padding(2)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Circle())
                            .padding(2)
                            .frame(width: 52, height: 52, alignment: .topLeading)
                        
                    case .inProgress(let progress):
                        if progress > 0 {
                            GeometryReader { geo in
                                let barWidth = geo.size.width
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.4))
                                        .frame(height: 2.5)
                                    
                                    Rectangle()
                                        .fill(Color.blue)
                                        .frame(width: max(0, min(barWidth, barWidth * progress)), height: 2.5)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                    case .unwatched:
                        EmptyView()
                    }
                    
                    Image(systemName: "video.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Circle())
                        .padding(2)
                        .frame(width: 52, height: 52, alignment: .bottomTrailing)
                } else if item.isGIF {
                    Text(.Strings.galleryBadgeGif)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(2)
                        .frame(width: 52, height: 52, alignment: .bottomTrailing)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body)
                        .lineLimit(1)
                    if FavoritesManager.shared.isFavorite(item) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                HStack(spacing: 6) {
                    Text(item.formattedSize)
                    if let dateStr = item.formattedDate {
                        Text("•")
                        Text(dateStr)
                    }
                    if item.isVideo {
                        let status = VideoPlaybackStore.shared.status(for: item)
                        switch status {
                        case .finished:
                            Text("•")
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                Text(.Strings.galleryBadgeWatched)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.green)
                        case .inProgress(let progress):
                            Text("•")
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 8, weight: .bold))
                                Text(progress > 0 ? "\(Int(progress * 100))%" : .Strings.galleryBadgeInProgress)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.blue)
                        case .unwatched:
                            EmptyView()
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onAppear {
            if thumbnail == nil {
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
            let loaded = await manager.downloadThumbnail(for: item, maxDimension: 140)
            guard !Task.isCancelled else { return }
            
            if let loaded {
                withAnimation(.easeIn(duration: 0.2)) {
                    self.thumbnail = loaded
                    self.loadFailed = false
                }
            } else if item.isVideo {
                if retryCount < 1 {
                    retryCount += 1
                    try? await Task.sleep(for: .milliseconds(1500))
                    guard !Task.isCancelled && self.thumbnail == nil else { return }
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
