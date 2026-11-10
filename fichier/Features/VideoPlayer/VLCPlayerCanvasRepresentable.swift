//
//  VLCPlayerCanvasRepresentable.swift
//  fichier
//

import SwiftUI
import UIKit
import FichierKit

/// SwiftUI wrapper embedding `FichierKit.TVVLCPlayerEngine`'s rendering view within the unified video player canvas.
///
/// Handles view lifecycle and two-finger gesture forwarding to preserve identical interactions
/// across both native and extended video backends.
public struct VLCPlayerCanvasRepresentable: UIViewRepresentable {
    /// Active extended player engine.
    public let engine: TVVLCPlayerEngine
    
    /// Callback triggered upon recognizing a single tap.
    public var onSingleTap: (() -> Void)?
    
    /// Callback triggered upon recognizing a two-finger single tap.
    public var onTwoFingerTap: (() -> Void)?
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - engine: Active extended player engine.
    ///   - onSingleTap: Optional single tap gesture callback.
    ///   - onTwoFingerTap: Optional two-finger tap gesture callback.
    public init(
        engine: TVVLCPlayerEngine,
        onSingleTap: (() -> Void)? = nil,
        onTwoFingerTap: (() -> Void)? = nil
    ) {
        self.engine = engine
        self.onSingleTap = onSingleTap
        self.onTwoFingerTap = onTwoFingerTap
    }
    
    public func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .black
        
        mountRenderView(in: container)
        
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(VLCPlayerCanvasCoordinator.handleSingleTap))
        #if !os(tvOS)
        singleTap.numberOfTouchesRequired = 1
        #endif
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false
        singleTap.delegate = context.coordinator
        container.addGestureRecognizer(singleTap)
        
        #if !os(tvOS)
        let twoFingerTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(VLCPlayerCanvasCoordinator.handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.cancelsTouchesInView = false
        twoFingerTap.delegate = context.coordinator
        container.addGestureRecognizer(twoFingerTap)
        #endif
        
        return container
    }
    
    public func updateUIView(_ uiView: UIView, context: Context) {
        mountRenderView(in: uiView)
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onTwoFingerTap = onTwoFingerTap
    }
    
    public func makeCoordinator() -> VLCPlayerCanvasCoordinator {
        VLCPlayerCanvasCoordinator(onSingleTap: onSingleTap, onTwoFingerTap: onTwoFingerTap)
    }

    private func mountRenderView(in container: UIView) {
        let renderView = engine.renderView
        if renderView.superview !== container {
            for subview in container.subviews where subview !== renderView {
                subview.removeFromSuperview()
            }
            renderView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(renderView)
            NSLayoutConstraint.activate([
                renderView.topAnchor.constraint(equalTo: container.topAnchor),
                renderView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                renderView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                renderView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        engine.attachDrawable()
    }
}
