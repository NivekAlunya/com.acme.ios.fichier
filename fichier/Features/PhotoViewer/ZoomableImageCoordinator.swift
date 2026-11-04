//
//  ZoomableImageCoordinator.swift
//  fichier
//

import UIKit

/// Coordinator managing `UIScrollViewDelegate` callbacks and tap gestures for interactive photo zooming.
///
/// Implements:
/// - `viewForZooming(in:)` returning the embedded `UIImageView`.
/// - Single tap gesture forwarding to toggle HUD control visibility.
/// - Double tap gesture calculating a 2.5x targeted zoom rect around the tap coordinate,
///   or toggling back to 1.0x minimum zoom if already enlarged.
@MainActor
final class ZoomableImageCoordinator: NSObject, UIScrollViewDelegate {
    /// Weak reference to the target image view being scaled.
    weak var imageView: UIImageView?
    
    /// Single tap callback invoked to show or hide the overlay toolbars.
    var onTap: () -> Void
    
    /// Current image reference used to detect updates across SwiftUI body evaluations.
    var currentImage: UIImage

    /// Memberwise initializer.
    ///
    /// - Parameters:
    ///   - onTap: Single tap handler.
    ///   - currentImage: Active image reference.
    init(onTap: @escaping () -> Void, currentImage: UIImage) {
        self.onTap = onTap
        self.currentImage = currentImage
    }

    /// Delegate method directing the scroll view to zoom the nested image view.
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    /// Action handler for single-tap gestures.
    @objc func handleSingleTap() {
        onTap()
    }

    /// Action handler for double-tap gestures, toggling between 1.0x fit-to-screen and 2.5x targeted zoom.
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
