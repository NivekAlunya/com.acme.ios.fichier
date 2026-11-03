//
//  VideoPlayerCenterControlsView.swift
//  fichier
//

import SwiftUI

public struct VideoPlayerCenterControlsView: View {
    public var controller: VideoPlayerController
    
    public init(controller: VideoPlayerController) {
        self.controller = controller
    }
    
    public var body: some View {
        ZStack {
            // Buffering Spinner
            if controller.playbackState.isBuffering && controller.errorMessage == nil {
                VStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                    Text(.Strings.videoPlayerBuffering)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .transition(.opacity)
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
                    .tint(.blue)
                    .accessibilityLabel(String(localized: "Retry Loading Video", comment: "Accessibility label to retry loading video"))
                }
            }
            
            // Center Play / Pause Toggle
            if !controller.playbackState.isBuffering && controller.errorMessage == nil {
                Button {
                    controller.togglePlayPause()
                } label: {
                    Image(systemName: controller.playbackState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(controller.playbackState.isPlaying ? String(localized: "Pause", comment: "Accessibility label to pause playback") : String(localized: "Play", comment: "Accessibility label to start playback"))
                .transition(.opacity)
            }
            
            // Side Navigation Arrows
            if controller.videos.count > 1 {
                HStack {
                    Button {
                        controller.goToPrevious()
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 42))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                    }
                    .accessibilityLabel(String(localized: "Previous Video", comment: "Accessibility label for previous video"))
                    .padding(.leading, 18)
                    
                    Spacer()
                    
                    Button {
                        controller.goToNext()
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 42))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                    }
                    .accessibilityLabel(String(localized: "Next Video", comment: "Accessibility label for next video"))
                    .padding(.trailing, 18)
                }
            }
        }
    }
}
