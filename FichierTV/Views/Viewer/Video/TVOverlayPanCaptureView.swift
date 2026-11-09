//
//  TVOverlayPanCaptureView.swift
//  FichierTV
//
//

import SwiftUI
import UIKit

/// `UIViewRepresentable` bridging Siri Remote touchpad horizontal swipe scrubbing into `TVVideoOverlayControlsView`.
///
/// NOTE: UIKit is utilized here because SwiftUI on tvOS cannot capture indirect touchpad pan translation
/// and velocity without stealing Focus Engine vertical transitions.
public struct TVOverlayPanCaptureView: UIViewRepresentable {
    public let isEnabled: Bool
    public let onPanChanged: @MainActor (_ incrementalDeltaX: CGFloat, _ velocityX: CGFloat, _ hostWidth: CGFloat) -> Void
    public let onPanEnded: @MainActor () -> Void
    public let onPanCancelled: @MainActor () -> Void

    public init(
        isEnabled: Bool,
        onPanChanged: @escaping @MainActor (_ incrementalDeltaX: CGFloat, _ velocityX: CGFloat, _ hostWidth: CGFloat) -> Void,
        onPanEnded: @escaping @MainActor () -> Void,
        onPanCancelled: @escaping @MainActor () -> Void
    ) {
        self.isEnabled = isEnabled
        self.onPanChanged = onPanChanged
        self.onPanEnded = onPanEnded
        self.onPanCancelled = onPanCancelled
    }

    public func makeUIView(context: Context) -> TVOverlayPanCaptureUIView {
        let view = TVOverlayPanCaptureUIView(frame: .zero)
        configure(view)
        return view
    }

    public func updateUIView(_ uiView: TVOverlayPanCaptureUIView, context: Context) {
        configure(uiView)
    }

    private func configure(_ view: TVOverlayPanCaptureUIView) {
        view.isScrubberSwipeEnabled = isEnabled
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
        view.onPanCancelled = onPanCancelled
    }
}
