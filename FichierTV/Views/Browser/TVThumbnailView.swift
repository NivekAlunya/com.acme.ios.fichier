//
//  TVThumbnailView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Asynchronously loads and renders downsampled thumbnails with cooperative cancellation.
public struct TVThumbnailView: View {
    public let item: MediaSourceItem
    public let targetSize: CGSize

    @State private var thumbnailImage: UIImage?
    @State private var isLoading = false

    public init(item: MediaSourceItem, targetSize: CGSize) {
        self.item = item
        self.targetSize = targetSize
    }

    public var body: some View {
        ZStack {
            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            } else {
                placeholderView
            }
        }
        .clipped()
        .task(id: item.id) {
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        ZStack {
            Color.secondary.opacity(0.15)

            Image(systemName: iconName)
                .font(.system(size: min(targetSize.width, targetSize.height) * 0.35))
                .foregroundStyle(.secondary)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
            }
        }
    }

    private var iconName: String {
        switch item.type {
        case .folder:
            return "folder.fill"
        case .video:
            return "video.fill"
        case .image:
            return "photo.fill"
        }
    }

    private func loadThumbnail() async {
        thumbnailImage = nil
        isLoading = true
        defer { isLoading = false }

        if let loaded = await fetchThumbnailOnce() {
            if !Task.isCancelled {
                thumbnailImage = loaded
            }
            return
        }

        if item.type == .video && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            if let retried = await fetchThumbnailOnce(), !Task.isCancelled {
                thumbnailImage = retried
            }
        }
    }

    private func fetchThumbnailOnce() async -> UIImage? {
        if let phID = item.phAssetIdentifier {
            return await PhotoThumbnailLoader.shared.loadThumbnail(for: phID, targetSize: targetSize)
        } else if item.type == .video {
            if let localURL = item.localURL, localURL.isFileURL {
                return await SMBVideoThumbnailLoader.shared.loadThumbnail(
                    from: localURL,
                    fileName: item.name,
                    targetSize: targetSize
                )
            } else if let sourceID = item.sourceID,
                      let share = item.smbShare,
                      let path = item.smbPath {
                return await SMBVideoThumbnailLoader.shared.loadThumbnail(
                    sourceID: sourceID,
                    share: share,
                    path: path,
                    fileName: item.name,
                    fileSize: item.size,
                    targetSize: targetSize
                )
            } else {
                return nil
            }
        } else if item.type == .image {
            if let localURL = item.localURL, localURL.isFileURL {
                return await SMBImageLoader.shared.loadLocalThumbnail(
                    url: localURL,
                    targetSize: targetSize
                )
            } else if let sourceID = item.sourceID,
                      let share = item.smbShare,
                      let path = item.smbPath {
                return await SMBImageLoader.shared.loadThumbnail(
                    sourceID: sourceID,
                    share: share,
                    path: path,
                    targetSize: targetSize
                )
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
}

#Preview {
    TVThumbnailView(
        item: MediaSourceItem(
            id: "123",
            name: "image.jpg",
            path: "image.jpg",
            type: .image,
            localURL: URL(string: "https://www.example.com/image.jpg")
        ),
        targetSize: CGSize(width: 380, height: 260)
    )
}
