//
//  VideoPlayerHUDView.swift
//  fichier
//

import SwiftUI

/// Composed overlay layer integrating top, center, and bottom HUD controls for video playback.
///
/// Features smooth animated fading (`opacity`) based on `controller.showControls`, and suppresses
/// touch hit testing when controls are invisible so background gestures pass directly to the player canvas.
public struct VideoPlayerHUDView: View {
    /// Active video player controller.
    public var controller: VideoPlayerController
    
    /// Callback triggered upon tapping the top bar dismiss button.
    public var onDismiss: () -> Void
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - controller: Active video player controller.
    ///   - onDismiss: Dismissal handler.
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
