//
//  VideoPlayerBottomBarView.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Floating translucent bottom bar for the video player HUD.
///
/// Features:
/// - Top row displaying the video title, playlist position (`1 of 12`), and formatted file size.
/// - Bottom row embedding `VideoTimelineBar` for interactive progress tracking and timeline scrubbing.
public struct VideoPlayerBottomBarView: View {
    /// Active video player controller.
    public var controller: VideoPlayerController
    
    /// Designated public initializer.
    ///
    /// - Parameter controller: Active video player controller.
    public init(controller: VideoPlayerController) {
        self.controller = controller
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Row 1: Prominent Video Title & File Info
            HStack(spacing: 8) {
                Text(controller.currentItem.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer(minLength: 8)
                
                Text(.Strings.commonItemCounterAndSize(controller.currentIndex + 1, controller.videos.count, controller.currentItem.formattedSize))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            
            // Row 2: Playback Timeline Scrubber
            VideoTimelineBar(
                currentTime: controller.currentPlaybackSeconds,
                duration: controller.totalDurationSeconds,
                chapters: controller.availableChapters,
                tintColor: controller.engineKind == .extended ? .orange : .blue,
                onSeek: { targetSeconds in
                    controller.onTimelineSeek(targetSeconds: targetSeconds)
                },
                onScrubbing: { targetSeconds in
                    controller.onTimelineScrubbing(targetSeconds: targetSeconds)
                },
                onScrubStateChanged: { isScrubbing in
                    controller.onTimelineScrubStateChanged(isScrubbing: isScrubbing)
                }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
    }
}
