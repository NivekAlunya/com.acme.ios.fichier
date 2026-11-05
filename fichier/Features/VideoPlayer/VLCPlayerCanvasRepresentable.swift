//
//  VLCPlayerCanvasRepresentable.swift
//  fichier
//

import SwiftUI
import UIKit

/// SwiftUI wrapper embedding MobileVLCKit's rendering view within the unified video player canvas.
///
/// Handles view lifecycle and two-finger gesture forwarding to preserve identical interactions
/// across both native and extended video backends.
public struct VLCPlayerCanvasRepresentable: UIViewRepresentable {
    /// Active extended player engine.
    public let engine: ExtendedPlayerEngine
    
    /// Callback triggered upon recognizing a two-finger single tap.
    public var onTwoFingerTap: (() -> Void)?
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - engine: Active extended player engine.
    ///   - onTwoFingerTap: Optional two-finger tap gesture callback.
    public init(
        engine: ExtendedPlayerEngine,
        onTwoFingerTap: (() -> Void)? = nil
    ) {
        self.engine = engine
        self.onTwoFingerTap = onTwoFingerTap
    }
    
    public func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .black
        
        let renderView = engine.renderView
        renderView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(renderView)
        
        NSLayoutConstraint.activate([
            renderView.topAnchor.constraint(equalTo: container.topAnchor),
            renderView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            renderView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            renderView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        let twoFingerTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(VLCPlayerCanvasCoordinator.handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.numberOfTapsRequired = 1
        container.addGestureRecognizer(twoFingerTap)
        
        return container
    }
    
    public func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTwoFingerTap = onTwoFingerTap
    }
    
    public func makeCoordinator() -> VLCPlayerCanvasCoordinator {
        VLCPlayerCanvasCoordinator(onTwoFingerTap: onTwoFingerTap)
    }
}
