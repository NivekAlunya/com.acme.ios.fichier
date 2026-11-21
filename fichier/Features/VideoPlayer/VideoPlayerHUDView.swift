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
        // Center Controls & Buffering / Error Overlay remain independent of showControls
        VideoPlayerCenterControlsView(controller: controller)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                VStack(spacing: 12) {
                    VideoPlayerTopBarView(controller: controller, onDismiss: onDismiss)
                    VideoPlayerToastBannerView(controller: controller)
                }
                .opacity(controller.showControls ? 1 : 0)
                .allowsHitTesting(controller.showControls)
                .accessibilityHidden(!controller.showControls)
                .transaction { $0.animation = nil }
            }
            .overlay(alignment: .bottom) {
                VideoPlayerBottomBarView(controller: controller)
                    .opacity(controller.showControls ? 1 : 0)
                    .allowsHitTesting(controller.showControls)
                    .accessibilityHidden(!controller.showControls)
                    .transaction { $0.animation = nil }
            }
    }
}
