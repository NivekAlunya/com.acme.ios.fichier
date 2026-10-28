//
//  ZoomableImageCoordinator.swift
//  fichier
//

import UIKit

final class ZoomableImageCoordinator: NSObject, UIScrollViewDelegate {
    weak var imageView: UIImageView?
    var onTap: () -> Void
    var currentImage: UIImage

    init(onTap: @escaping () -> Void, currentImage: UIImage) {
        self.onTap = onTap
        self.currentImage = currentImage
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    @objc func handleSingleTap() {
        onTap()
    }

    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let scrollView = gesture.view as? UIScrollView else { return }
        if scrollView.zoomScale > 1.0 {
            scrollView.setZoomScale(1.0, animated: true)
        } else {
            let location = gesture.location(in: imageView)
            let zoomRect = CGRect(
                x: location.x - (scrollView.bounds.width / 5.0),
                y: location.y - (scrollView.bounds.height / 5.0),
                width: scrollView.bounds.width / 2.5,
                height: scrollView.bounds.height / 2.5
            )
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }
}
