//
//  ZoomableImageView.swift
//  fichier
//

import SwiftUI
import UIKit

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let onTap: () -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4.0
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])

        // Single tap gesture (toggle controls)
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(ZoomableImageCoordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        scrollView.addGestureRecognizer(singleTap)

        // Double tap gesture (zoom in / out)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(ZoomableImageCoordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Single tap waits briefly so double tap is detected first
        singleTap.require(toFail: doubleTap)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if context.coordinator.currentImage != image {
            context.coordinator.currentImage = image
            context.coordinator.imageView?.image = image
            uiView.setZoomScale(1.0, animated: false)
        }
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> ZoomableImageCoordinator {
        ZoomableImageCoordinator(onTap: onTap, currentImage: image)
    }
}
