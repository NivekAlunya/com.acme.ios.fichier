//
//  HorizontalSeekGestureView.swift
//  fichier
//
//  Created on 2026-11-24.
//

#if !os(tvOS)
import SwiftUI
import UIKit

/// Transparent UIKit overlay capturing horizontal pans for timeline scrubbing while
/// letting vertical pans pass through to `.navigationTransition(.zoom)` dismissal.
struct HorizontalSeekGestureView: UIViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void
    let onTap: () -> Void

    func makeCoordinator() -> HorizontalSeekGestureCoordinator {
        HorizontalSeekGestureCoordinator(
            onChanged: onChanged,
            onEnded: onEnded,
            onTap: onTap
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

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(HorizontalSeekGestureCoordinator.handleTap)
        )
        tap.require(toFail: pan)
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onTap = onTap
    }
}
#endif
