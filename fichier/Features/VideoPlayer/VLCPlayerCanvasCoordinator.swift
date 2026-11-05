//
//  VLCPlayerCanvasCoordinator.swift
//  fichier
//

import UIKit

/// Coordinator managing gesture recognition callbacks for `VLCPlayerCanvasRepresentable`.
@MainActor
public final class VLCPlayerCanvasCoordinator: NSObject {
    var onTwoFingerTap: (() -> Void)?
    
    init(onTwoFingerTap: (() -> Void)?) {
        self.onTwoFingerTap = onTwoFingerTap
    }
    
    @objc func handleTwoFingerTap() {
        onTwoFingerTap?()
    }
}
