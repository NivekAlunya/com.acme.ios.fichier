//
//  HorizontalSeekGestureView.swift
//  fichier
//
//  Created on 2026-11-24.
//

#if !os(tvOS)
import SwiftUI
import UIKit

/// Transparent UIKit overlay capturing horizontal pans for timeline scrubbing,
/// single taps for HUD toggling, and two-finger taps for play/pause.
struct HorizontalSeekGestureView: UIViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void
    let onTap: () -> Void
    let onTwoFingerTap: () -> Void

    func makeCoordinator() -> HorizontalSeekGestureCoordinator {
        HorizontalSeekGestureCoordinator(
            onChanged: onChanged,
            onEnded: onEnded,
            onTap: onTap,
            onTwoFingerTap: onTwoFingerTap
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(HorizontalSeekGestureCoordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let twoFingerTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(HorizontalSeekGestureCoordinator.handleTwoFingerTap)
        )
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.numberOfTapsRequired = 1
        view.addGestureRecognizer(twoFingerTap)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(HorizontalSeekGestureCoordinator.handleTap)
        )
        tap.numberOfTouchesRequired = 1
        tap.numberOfTapsRequired = 1
        tap.require(toFail: pan)
        tap.require(toFail: twoFingerTap)
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onTap = onTap
        context.coordinator.onTwoFingerTap = onTwoFingerTap
    }
}
#endif
