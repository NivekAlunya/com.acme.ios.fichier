//
//  VideoPlayerCenterControlsView.swift
//  fichier
//

import SwiftUI
import AVFoundation
import FichierKit

/// Centered controls overlay presenting playback indicators, large play/pause toggles, and transport navigation.
///
/// Features:
/// - Indeterminate buffering spinner with "Buffering..." caption when loading or network stalled (remains visible until buffering finishes).
/// - Descriptive error notification with a retry button upon failure.
/// - Unified transport cluster: 15s Backward (42pt), Play/Pause/Replay (64pt), and 15s Forward (42pt) buttons.
public struct VideoPlayerCenterControlsView: View {
    /// Two-way reference to the active video player controller.
    public var controller: VideoPlayerController
    
    /// Designated public initializer.
    ///
    /// - Parameter controller: Active video player controller.
    public init(controller: VideoPlayerController) {
        self.controller = controller
    }
    
    public var body: some View {
        let isActivelyBuffering = controller.playbackState.isBuffering && !controller.isEnginePlaying
        
        ZStack {
            // Buffering Spinner (remains visible until buffering is done, independent of showControls)
            if isActivelyBuffering && controller.errorMessage == nil {
                VStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                    Text(.Strings.videoPlayerBuffering)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                .transition(.opacity)
                .allowsHitTesting(false)
            }
            
            // Error Message
            if let error = controller.errorMessage {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button(.Strings.commonRetry) {
                        controller.setupPlayer(for: controller.currentItem)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FichierTheme.secondaryAccent)
                    .accessibilityLabel(Text(.Strings.videoPlayerControlRetryLoading))
                }
                .transition(.opacity)
            }
            
            // Central Transport Controls (Backward 15s, Play/Pause/Replay, Forward 15s)
            // Controlled by showControls so they fade in/out with the rest of the UI elements
            if !isActivelyBuffering && controller.errorMessage == nil {
                HStack(spacing: 36) {
                    // Backward 15s Button
                    Button {
                        controller.seekRelative(-15)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 42))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(.Strings.videoPlayerControlBackward15))
                    
                    // Center Play / Pause / Replay Toggle
                    Button {
                        controller.togglePlayPause()
                    } label: {
                        Image(systemName: controller.isAtEnd ? "arrow.counterclockwise.circle.fill" : (controller.playbackState.isPlaying ? "pause.circle.fill" : "play.circle.fill"))
                            .font(.system(size: 64))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(controller.isAtEnd ? Text(.Strings.commonReplay) : (controller.playbackState.isPlaying ? Text(.Strings.commonPause) : Text(.Strings.commonPlay)))
                    
                    // Forward 15s Button
                    Button {
                        controller.seekRelative(15)
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 42))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(.Strings.videoPlayerControlForward15))
                }
                .opacity(controller.showControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: controller.showControls)
                .allowsHitTesting(controller.showControls)
                .accessibilityHidden(!controller.showControls)
                .transition(.opacity)
            }
        }
    }
}
