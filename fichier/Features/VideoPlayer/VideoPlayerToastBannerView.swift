//
//  VideoPlayerToastBannerView.swift
//  fichier
//

import SwiftUI

/// Floating translucent notification capsules rendered beneath the top bar in the video player HUD.
///
/// Displays:
/// 1. **Playback Resume Notification**: Indicates the restored timestamp with an interactive "Restart" pill button.
/// 2. **Save to Camera Roll Confirmation**: Displays a checkmark badge when video export completes.
public struct VideoPlayerToastBannerView: View {
    /// Two-way reference to the active video player controller.
    public var controller: VideoPlayerController
    
    /// Designated public initializer.
    ///
    /// - Parameter controller: Active video player controller.
    public init(controller: VideoPlayerController) {
        self.controller = controller
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            if let resumeMessage = controller.resumedToastMessage {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .foregroundColor(.blue)
                    Text(resumeMessage)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Button {
                        controller.restartVideo()
                    } label: {
                        Text(.Strings.videoPlayerRestartButton)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.blue))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Restart from beginning", comment: "Accessibility label to restart playback from start"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if let saveMessage = controller.saveStatusMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(saveMessage)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}
