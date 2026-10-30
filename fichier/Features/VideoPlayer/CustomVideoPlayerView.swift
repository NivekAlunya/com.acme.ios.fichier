//
//  CustomVideoPlayerView.swift
//  fichier
//

import SwiftUI
import AVKit

public struct CustomVideoPlayerView: UIViewRepresentable {
    public let player: AVPlayer
    public let coordinator: CustomVideoPlayerCoordinator
    public var onPiPStatusChanged: ((Bool) -> Void)?
    public var onTwoFingerTap: (() -> Void)?
    
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
