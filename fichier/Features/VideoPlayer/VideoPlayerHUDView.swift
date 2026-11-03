//
//  VideoPlayerHUDView.swift
//  fichier
//

import SwiftUI

public struct VideoPlayerHUDView: View {
    public var controller: VideoPlayerController
    public var onDismiss: () -> Void
    
    public init(controller: VideoPlayerController, onDismiss: @escaping () -> Void) {
        self.controller = controller
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        ZStack {
            VStack(spacing: 12) {
                VideoPlayerTopBarView(controller: controller, onDismiss: onDismiss)
                
                VideoPlayerToastBannerView(controller: controller)
                
                Spacer()
                
                VideoPlayerBottomBarView(controller: controller)
            }
            
            VideoPlayerCenterControlsView(controller: controller)
        }
        .opacity(controller.showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: controller.showControls)
        .animation(.easeInOut(duration: 0.25), value: controller.playbackState.isBuffering)
        .allowsHitTesting(controller.showControls)
    }
}
