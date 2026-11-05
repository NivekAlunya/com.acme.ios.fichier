//
//  VLCPlayerCanvasCoordinator.swift
//  fichier
//

import UIKit

/// Coordinator managing gesture recognition callbacks for `VLCPlayerCanvasRepresentable`.
@MainActor
public final class VLCPlayerCanvasCoordinator: NSObject, UIGestureRecognizerDelegate {
    var onSingleTap: (() -> Void)?
    var onTwoFingerTap: (() -> Void)?
    
    init(onSingleTap: (() -> Void)?, onTwoFingerTap: (() -> Void)?) {
        self.onSingleTap = onSingleTap
        self.onTwoFingerTap = onTwoFingerTap
    }
    
    @objc func handleSingleTap() {
        onSingleTap?()
    }
    
    @objc func handleTwoFingerTap() {
        onTwoFingerTap?()
    }
    
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
