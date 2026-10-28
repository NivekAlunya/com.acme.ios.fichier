//
//  ZoomablePicturePageView.swift
//  fichier
//

import SwiftUI

struct ZoomablePicturePageView: View {
    var manager: SMBDirectManager
    let item: SMBItem
    let onImageLoaded: (UIImage) -> Void
    let onTap: () -> Void
    
    @State private var image: UIImage?
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
                    Text("Failed to load picture")
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
