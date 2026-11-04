//
//  ZoomablePicturePageView.swift
//  fichier
//

import SwiftUI

/// Page container view managing asynchronous full-resolution image download and pinch-to-zoom presentation.
///
/// Executes an asynchronous `.task(id: item.id)` querying `manager.downloadImage(for:)`.
/// Upon retrieval, renders `ZoomableImageView` and calls `onImageLoaded` to notify parent toolbars
/// that the image is ready for sharing or saving.
struct ZoomablePicturePageView: View {
    /// Shared storage location manager handling image retrieval.
    var manager: StorageLocationManager
    
    /// Target photo media item.
    let item: MediaItem
    
    /// Callback delivering the successfully decoded `UIImage` to the parent view.
    let onImageLoaded: (UIImage) -> Void
    
    /// Single tap callback forwarded to toggle HUD visibility.
    let onTap: () -> Void
    
    /// Successfully downloaded and decoded full-resolution image.
    @State private var image: UIImage?
    
    /// Indicates whether image loading is currently in flight.
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let image {
                ZoomableImageView(image: image, onTap: onTap)
            } else if isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.3)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.5))
                    Text(.Strings.photoViewerErrorFailedToLoad)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .task(id: item.id) {
            if let img = await manager.downloadImage(for: item) {
                self.image = img
                onImageLoaded(img)
            }
            self.isLoading = false
        }
    }
}
