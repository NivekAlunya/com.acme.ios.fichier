//
//  VideoPlayerHUDView.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Composed overlay layer integrating top, center, and bottom HUD controls for video playback.
///
/// Features smooth animated fading (`opacity`) for transient control bars and transport buttons based on
/// `controller.showControls`, while keeping persistent status indicators (such as the buffering spinner)
/// visible until buffering completes.
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
            // Bars & Overlays (Top, Toast, Bottom) - explicitly tied to showControls
            VStack(spacing: 12) {
                VideoPlayerTopBarView(controller: controller, onDismiss: onDismiss)
                
                VideoPlayerToastBannerView(controller: controller)
                
                Spacer()
                
                VideoPlayerBottomBarView(controller: controller)
            }
            .opacity(controller.showControls ? 1 : 0)
            .animation(.easeInOut(duration: 0.35), value: controller.showControls)
            .allowsHitTesting(controller.showControls)
            .accessibilityHidden(!controller.showControls)
            
            // Center Controls & Buffering / Error Overlay
            // The buffering popup and error indicator remain independent of showControls
            // so buffering stays visible until buffering is done!
            VideoPlayerCenterControlsView(controller: controller)
        }
        .animation(.easeInOut(duration: 0.25), value: controller.playbackState.isBuffering)
    }
}
