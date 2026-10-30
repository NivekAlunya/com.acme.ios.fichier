//
//  CustomVideoPlayerView.swift
//  fichier
//

import SwiftUI
import AVKit

public struct CustomVideoPlayerView: UIViewControllerRepresentable {
    public let player: AVPlayer
    public var showsPlaybackControls: Bool
    public var onPiPStatusChanged: ((Bool) -> Void)?
    public var onCoordinatorReady: ((CustomVideoPlayerCoordinator) -> Void)?
    
    public init(
        player: AVPlayer,
        showsPlaybackControls: Bool = false,
        onPiPStatusChanged: ((Bool) -> Void)? = nil,
        onCoordinatorReady: ((CustomVideoPlayerCoordinator) -> Void)? = nil
    ) {
        self.player = player
        self.showsPlaybackControls = showsPlaybackControls
        self.onPiPStatusChanged = onPiPStatusChanged
        self.onCoordinatorReady = onCoordinatorReady
    }
    
    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsPlaybackControls
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        controller.delegate = context.coordinator
        context.coordinator.onPiPStatusChanged = onPiPStatusChanged
        onCoordinatorReady?(context.coordinator)
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
        uiViewController.showsPlaybackControls = showsPlaybackControls
        uiViewController.allowsPictureInPicturePlayback = true
        uiViewController.canStartPictureInPictureAutomaticallyFromInline = true
        context.coordinator.onPiPStatusChanged = onPiPStatusChanged
        
        DispatchQueue.main.async {
            setupPiP(in: uiViewController, coordinator: context.coordinator)
        }
    }
    
    public func makeCoordinator() -> CustomVideoPlayerCoordinator {
        CustomVideoPlayerCoordinator()
    }
    
    private func setupPiP(in controller: AVPlayerViewController, coordinator: CustomVideoPlayerCoordinator) {
        guard coordinator.pipController == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if let playerLayer = findPlayerLayer(in: controller.view) {
            let pip = AVPictureInPictureController(playerLayer: playerLayer)
            pip?.canStartPictureInPictureAutomaticallyFromInline = true
            pip?.delegate = coordinator
            coordinator.pipController = pip
        }
    }
    
    private func findPlayerLayer(in view: UIView) -> AVPlayerLayer? {
        if let layer = view.layer as? AVPlayerLayer { return layer }
        for sublayer in view.layer.sublayers ?? [] {
            if let pl = sublayer as? AVPlayerLayer { return pl }
        }
        for subview in view.subviews {
            if let found = findPlayerLayer(in: subview) { return found }
        }
        return nil
    }
}
