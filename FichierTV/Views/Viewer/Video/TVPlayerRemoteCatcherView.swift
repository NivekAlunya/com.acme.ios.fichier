//
//  TVPlayerRemoteCatcherView.swift
//  FichierTV
//
//

import SwiftUI

/// `UIViewRepresentable` hosting `TVPlayerRemoteCatcherUIView` to capture Siri Remote
/// press-to-release seeking durations when the full HUD overlay is hidden.
public struct TVPlayerRemoteCatcherView: UIViewRepresentable {
    public let isEnabled: Bool
    public let shouldRequestFocus: Bool
    public let onSeekPressBegan: @MainActor (Bool, TimeInterval) -> Void
    public let onSeekPressEnded: @MainActor (Bool, TimeInterval) -> Void
    public let onSeekPressCancelled: @MainActor (Bool) -> Void
    public let onRevealOverlay: @MainActor () -> Void

    public init(
        isEnabled: Bool,
        shouldRequestFocus: Bool,
        onSeekPressBegan: @escaping @MainActor (Bool, TimeInterval) -> Void,
        onSeekPressEnded: @escaping @MainActor (Bool, TimeInterval) -> Void,
        onSeekPressCancelled: @escaping @MainActor (Bool) -> Void,
        onRevealOverlay: @escaping @MainActor () -> Void
    ) {
        self.isEnabled = isEnabled
        self.shouldRequestFocus = shouldRequestFocus
        self.onSeekPressBegan = onSeekPressBegan
        self.onSeekPressEnded = onSeekPressEnded
        self.onSeekPressCancelled = onSeekPressCancelled
        self.onRevealOverlay = onRevealOverlay
    }

    public func makeUIView(context: Context) -> TVPlayerRemoteCatcherUIView {
        let view = TVPlayerRemoteCatcherUIView(frame: .zero)
        configure(view)
        return view
    }

    public func updateUIView(_ uiView: TVPlayerRemoteCatcherUIView, context: Context) {
        configure(uiView)
        if isEnabled && shouldRequestFocus && !uiView.isFocused {
            uiView.setNeedsFocusUpdate()
        }
    }

    private func configure(_ view: TVPlayerRemoteCatcherUIView) {
        view.isFocusCatchingEnabled = isEnabled
        view.onSeekPressBegan = onSeekPressBegan
        view.onSeekPressEnded = onSeekPressEnded
        view.onSeekPressCancelled = onSeekPressCancelled
        view.onRevealOverlay = onRevealOverlay
    }
}
