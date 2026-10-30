//
//  CustomVideoPlayerView.swift
//  fichier
//

import SwiftUI
import AVKit

public struct CustomVideoPlayerView: UIViewRepresentable {
    public let player: AVPlayer
    public var onPiPStatusChanged: ((Bool) -> Void)?
    public var onCoordinatorReady: ((CustomVideoPlayerCoordinator) -> Void)?
    
    public init(
        player: AVPlayer,
        onPiPStatusChanged: ((Bool) -> Void)? = nil,
        onCoordinatorReady: ((CustomVideoPlayerCoordinator) -> Void)? = nil
    ) {
        self.player = player
        self.onPiPStatusChanged = onPiPStatusChanged
        self.onCoordinatorReady = onCoordinatorReady
    }
    
    public func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        context.coordinator.setupPiP(with: view.playerLayer)
        context.coordinator.onPiPStatusChanged = onPiPStatusChanged
        onCoordinatorReady?(context.coordinator)
        return view
    }
    
    public func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
            context.coordinator.setupPiP(with: uiView.playerLayer)
        }
        context.coordinator.onPiPStatusChanged = onPiPStatusChanged
    }
    
    public func makeCoordinator() -> CustomVideoPlayerCoordinator {
        CustomVideoPlayerCoordinator()
    }
}
