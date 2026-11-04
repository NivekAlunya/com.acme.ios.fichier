//
//  CustomVideoPlayerView.swift
//  fichier
//

import SwiftUI
import AVKit

/// SwiftUI wrapper embedding `PlayerUIView` and configuring Picture-in-Picture.
///
/// Bridges the UIKit `PlayerUIView` layer hierarchy to SwiftUI, binding the active `AVPlayer`
/// and passing `AVPlayerLayer` to `CustomVideoPlayerCoordinator` to enable native PiP transitions.
public struct CustomVideoPlayerView: UIViewRepresentable {
    /// Active AVFoundation player instance.
    public let player: AVPlayer
    
    /// Picture-in-Picture lifecycle coordinator.
    public let coordinator: CustomVideoPlayerCoordinator
    
    /// Callback signaling changes in Picture-in-Picture presentation status.
    public var onPiPStatusChanged: ((Bool) -> Void)?
    
    /// Callback triggered upon recognizing a two-finger single tap.
    public var onTwoFingerTap: (() -> Void)?
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - player: Active AVPlayer.
    ///   - coordinator: PiP coordinator.
    ///   - onPiPStatusChanged: PiP status callback.
    ///   - onTwoFingerTap: Two-finger tap callback.
    public init(
        player: AVPlayer,
        coordinator: CustomVideoPlayerCoordinator,
        onPiPStatusChanged: ((Bool) -> Void)? = nil,
        onTwoFingerTap: (() -> Void)? = nil
    ) {
        self.player = player
        self.coordinator = coordinator
        self.onPiPStatusChanged = onPiPStatusChanged
        self.onTwoFingerTap = onTwoFingerTap
    }
    
    public func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.onTwoFingerTap = onTwoFingerTap
        coordinator.setupPiP(with: view.playerLayer)
        coordinator.onPiPStatusChanged = onPiPStatusChanged
        return view
    }
    
    public func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
            coordinator.setupPiP(with: uiView.playerLayer)
        }
        uiView.onTwoFingerTap = onTwoFingerTap
        coordinator.onPiPStatusChanged = onPiPStatusChanged
    }
    
    public func makeCoordinator() -> CustomVideoPlayerCoordinator {
        coordinator
    }
}
