//
//  HorizontalSeekGestureCoordinator.swift
//  fichier
//
//  Created on 2026-11-24.
//

#if !os(tvOS)
import UIKit

/// Coordinator managing horizontal-only pan recognition for video scrubbing.
///
/// Rejects vertical drags in `gestureRecognizerShouldBegin(_:)` so `.navigationTransition(.zoom)`
/// retains its native interactive swipe-down translation and scaling dismissal.
@MainActor
final class HorizontalSeekGestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void
    var onTap: () -> Void
    var onTwoFingerTap: () -> Void

    init(
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping () -> Void,
        onTap: @escaping () -> Void,
        onTwoFingerTap: @escaping () -> Void
    ) {
        self.onChanged = onChanged
        self.onEnded = onEnded
        self.onTap = onTap
        self.onTwoFingerTap = onTwoFingerTap
    }

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(recognizer.translation(in: recognizer.view).x)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    @objc func handleTap() {
        onTap()
    }

    @objc func handleTwoFingerTap() {
        onTwoFingerTap()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }
        let velocity = pan.velocity(in: pan.view)
        return abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
#endif
