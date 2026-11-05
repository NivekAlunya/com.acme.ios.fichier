//
//  VideoPlayerCanvasView.swift
//  fichier
//

import SwiftUI
import AVKit

/// Video playback canvas combining hardware video rendering with full-screen gesture scrubbing.
///
/// Features:
/// - Supports both native `AVPlayerLayer` (`CustomVideoPlayerView`) and extended MobileVLCKit (`VLCPlayerCanvasRepresentable`).
/// - Single tap gesture toggles HUD overlay visibility (`controller.toggleControls()`).
/// - Horizontal drag gesture (`videoSeekGesture`) enables scrubbing anywhere on the video canvas.
///   Calculates dynamic scrubbing sensitivity scaled to document length:
///   - Videos > 1 hour: 2.0× multiplier for rapid navigation.
///   - Videos > 10 minutes: 1.0× multiplier.
///   - Short clips: 0.5× multiplier for fine precision.
public struct VideoPlayerCanvasView: View {
    /// Active video player controller.
    public var controller: VideoPlayerController
    
    /// Designated public initializer.
    ///
    /// - Parameter controller: Active video player controller.
    public init(controller: VideoPlayerController) {
        self.controller = controller
    }
    
    public var body: some View {
        ZStack {
            switch controller.engineKind {
            case .native:
                if let player = controller.player {
                    CustomVideoPlayerView(
                        player: player,
                        coordinator: controller.pipCoordinator,
                        onPiPStatusChanged: { isActive in
                            controller.isPiPActive = isActive
                        },
                        onSingleTap: {
                            controller.toggleControls()
                        },
                        onTwoFingerTap: {
                            controller.handleTwoFingerTap()
                        }
                    )
                    .ignoresSafeArea()
                }
            case .extended:
                if let extended = controller.extendedEngine {
                    VLCPlayerCanvasRepresentable(
                        engine: extended,
                        onSingleTap: {
                            controller.toggleControls()
                        },
                        onTwoFingerTap: {
                            controller.handleTwoFingerTap()
                        }
                    )
                    .ignoresSafeArea()
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(videoSeekGesture)
        .onTapGesture {
            controller.toggleControls()
        }
    }
    
    /// Full-screen horizontal drag gesture for gesture-driven timeline scrubbing.
    private var videoSeekGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                guard !controller.seekCoordinator.isScrubbingTimeline else { return }
                let hTranslation = value.translation.width
                let vTranslation = value.translation.height
                guard let engine = controller.engine else { return }
                
                if !controller.seekCoordinator.isScrubbingWithGesture {
                    guard abs(hTranslation) > abs(vTranslation) else { return }
                    controller.seekCoordinator.startGestureScrubbing(
                        currentPlaybackSeconds: controller.currentPlaybackSeconds,
                        isPlaying: controller.playbackState.isPlaying,
                        engine: engine
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
                controller.seekCoordinator.requestLiveFrameSeek(to: target, engine: engine)
            }
            .onEnded { _ in
                guard controller.seekCoordinator.isScrubbingWithGesture else { return }
                controller.seekCoordinator.endGestureScrubbing()
                guard !controller.seekCoordinator.isScrubbingTimeline else { return }
                controller.finishSeeking(at: controller.currentPlaybackSeconds, resumePlaying: controller.seekCoordinator.wasPlayingBeforeScrub)
            }
    }
}
