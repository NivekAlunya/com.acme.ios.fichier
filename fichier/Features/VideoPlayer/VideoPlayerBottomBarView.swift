//
//  VideoPlayerBottomBarView.swift
//  fichier
//

import SwiftUI

public struct VideoPlayerBottomBarView: View {
    public var controller: VideoPlayerController
    
    public init(controller: VideoPlayerController) {
        self.controller = controller
    }
    
    public var body: some View {
        VideoTimelineBar(
            currentTime: controller.currentPlaybackSeconds,
            duration: controller.totalDurationSeconds,
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
        .padding(.horizontal, 24)
        .padding(.bottom, 2)
    }
}
