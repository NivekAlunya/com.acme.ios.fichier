//
//  VideoPlayerCanvasView.swift
//  fichier
//

import SwiftUI
import AVKit

public struct VideoPlayerCanvasView: View {
    public var controller: VideoPlayerController
    
    public init(controller: VideoPlayerController) {
        self.controller = controller
    }
    
    public var body: some View {
        ZStack {
            if let player = controller.player {
                CustomVideoPlayerView(
                    player: player,
                    coordinator: controller.pipCoordinator,
                    onPiPStatusChanged: { isActive in
                        controller.isPiPActive = isActive
                    },
                    onTwoFingerTap: {
                        controller.handleTwoFingerTap()
                    }
                )
                .ignoresSafeArea()
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(videoSeekGesture)
        .onTapGesture {
            controller.toggleControls()
        }
    }
    
    private var videoSeekGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                guard !controller.seekCoordinator.isScrubbingTimeline else { return }
                let hTranslation = value.translation.width
                let vTranslation = value.translation.height
                guard let player = controller.player else { return }
                
                if !controller.seekCoordinator.isScrubbingWithGesture {
                    guard abs(hTranslation) > abs(vTranslation) else { return }
                    controller.seekCoordinator.startGestureScrubbing(
                        currentPlaybackSeconds: controller.currentPlaybackSeconds,
                        isPlaying: controller.playbackState.isPlaying,
                        player: player
                    )
                    if controller.seekCoordinator.wasPlayingBeforeScrub {
                        controller.playbackState = .paused
                    }
                    controller.cancelAutoHideTimer()
                    withAnimation(.easeInOut(duration: 0.35)) {
                        controller.showControls = true
                    }
                }
                
                let sensitivity: Double
                if controller.totalDurationSeconds > 3600 {
                    sensitivity = 2.0
                } else if controller.totalDurationSeconds > 600 {
                    sensitivity = 1.0
                } else {
                    sensitivity = 0.5
                }
                
                let delta = Double(hTranslation) * sensitivity
                let maxTarget = (controller.totalDurationSeconds.isFinite && !controller.totalDurationSeconds.isNaN && controller.totalDurationSeconds > 0) ? controller.totalDurationSeconds : Double.greatestFiniteMagnitude
                let target = max(0, min(maxTarget, controller.seekCoordinator.initialScrubTime + delta))
                controller.currentPlaybackSeconds = target
                controller.seekCoordinator.requestLiveFrameSeek(to: target, player: player)
            }
            .onEnded { _ in
                guard controller.seekCoordinator.isScrubbingWithGesture else { return }
                controller.seekCoordinator.endGestureScrubbing()
                guard !controller.seekCoordinator.isScrubbingTimeline else { return }
                controller.finishSeeking(at: controller.currentPlaybackSeconds, resumePlaying: controller.seekCoordinator.wasPlayingBeforeScrub)
            }
    }
}
