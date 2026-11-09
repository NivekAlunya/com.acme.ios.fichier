//
//  TVVideoPlayerView.swift
//  FichierTV
//
//

import SwiftUI
import AVFoundation
import FichierKit

/// Full-screen tvOS Video Player integrating `AVPlayer` and `VLCKit` with custom two-row HUD (Section 6).
///
/// Implements full Siri Remote mapping:
/// - Directional presses reveal hidden overlay or navigate between progress scrubber and button rows.
/// - Play/Pause toggles playback unconditionally.
/// - Menu follows a 3-step cancellation hierarchy: abort scrub -> dismiss overlay -> pop navigation stack.
public struct TVVideoPlayerView: View {
    public let initialItem: MediaSourceItem
    public let videos: [MediaSourceItem]

    @State private var viewModel: TVVideoPlayerViewModel
    @FocusState private var isPlayerFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(initialItem: MediaSourceItem, videos: [MediaSourceItem]) {
        self.initialItem = initialItem
        self.videos = videos
        _viewModel = State(wrappedValue: TVVideoPlayerViewModel(initialItem: initialItem, videos: videos))
    }

    init(viewModel: TVVideoPlayerViewModel) {
        self.initialItem = viewModel.currentItem
        self.videos = viewModel.videos
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // Video Canvas (Native AVPlayer vs Extended VLCKit Drawable)
            switch viewModel.activeEngineKind {
            case .native:
                TVPlayerCanvasView(player: viewModel.nativeEngine.avPlayer)
                    .ignoresSafeArea()
            case .extended:
                TVVLCCanvasView(engine: viewModel.extendedEngine)
                    .ignoresSafeArea()
            }

            // Hidden-overlay remote catch target (removed when HUD or error overlay shows so buttons receive Focus Engine focus)
            if !viewModel.showOverlay && viewModel.errorMessage == nil {
                TVPlayerRemoteCatcherView(
                    isEnabled: !viewModel.showOverlay && viewModel.errorMessage == nil && !viewModel.isShowingTracksSheet && !viewModel.isShowingChaptersSheet,
                    shouldRequestFocus: isPlayerFocused,
                    onSeekPressBegan: { isForward, timestamp in
                        viewModel.beginRemoteSeek(
                            isForward: isForward,
                            source: .siriRemoteDirection,
                            timestamp: timestamp
                        )
                    },
                    onSeekPressEnded: { isForward, timestamp in
                        viewModel.endRemoteSeek(
                            isForward: isForward,
                            source: .siriRemoteDirection,
                            timestamp: timestamp
                        )
                    },
                    onSeekPressCancelled: { isForward in
                        viewModel.cancelRemoteSeek(
                            isForward: isForward,
                            source: .siriRemoteDirection
                        )
                    },
                    onRevealOverlay: {
                        viewModel.revealOverlay()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focused($isPlayerFocused)
            }

            // Live non-focusable seek preview pill + bar + thumbnail card during `<<`/`>>` remote taps and holds
            if !viewModel.showOverlay, viewModel.errorMessage == nil, let preview = viewModel.remoteSeekPreview {
                TVVideoSeekPreviewHUDView(
                    title: viewModel.currentItem.name,
                    duration: viewModel.duration,
                    preview: preview,
                    chapters: viewModel.availableChapters,
                    seekThumbnailState: viewModel.seekThumbnailState
                )
                .transition(reduceMotion ? .identity : .opacity)
            }

            // Buffering / Loading Indicator
            if viewModel.playbackState == .buffering || viewModel.playbackState == .loading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
            }

            // Error Overlay with Back / Retry actions
            if let error = viewModel.errorMessage {
                TVErrorStateView(
                    message: error,
                    onBack: {
                        dismiss()
                    },
                    onRetry: {
                        viewModel.loadCurrentVideo()
                    }
                )
            }

            // Custom HUD Overlay (Two Rows)
            if viewModel.showOverlay {
                TVVideoOverlayControlsView(
                    title: viewModel.currentItem.name,
                    currentTime: viewModel.currentTime,
                    duration: viewModel.duration,
                    isPlaying: viewModel.isPlaying,
                    isScrubbing: viewModel.isScrubbing,
                    scrubbingTime: viewModel.scrubbingTime,
                    chapters: viewModel.availableChapters,
                    seekThumbnailState: viewModel.seekThumbnailState,
                    remoteSeekPreview: viewModel.remoteSeekPreview,
                    isChaptersSheetPresented: viewModel.isShowingChaptersSheet,
                    isTracksSheetPresented: viewModel.isShowingTracksSheet,
                    initialFocusTarget: viewModel.currentFocusTarget,
                    onFocusChanged: { target in
                        viewModel.syncFocusTarget(target)
                    },
                    onScrubStep: { forward in
                        viewModel.stepScrub(forward: forward)
                    },
                    onSwipeScrubChanged: { deltaX, velocityX, trackWidth in
                        viewModel.updateSwipeScrub(
                            translationDeltaX: deltaX,
                            velocityX: velocityX,
                            trackWidth: trackWidth
                        )
                    },
                    onSwipeScrubEnded: {
                        viewModel.finishSwipeScrubInteraction()
                    },
                    onSwipeScrubCancelled: {
                        viewModel.finishSwipeScrubInteraction()
                    },
                    onScrubberSelect: {
                        viewModel.activateScrubberSelect()
                    },
                    onPrevious: { viewModel.previousVideo() },
                    onTogglePlayPause: { viewModel.togglePlayPause() },
                    onNext: { viewModel.nextVideo() },
                    onOpenChapters: { viewModel.openChaptersMenu() },
                    onOpenTracks: { viewModel.openTracksMenu() }
                )
                .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .onPlayPauseCommand {
            viewModel.handlePlayPauseCommand()
        }
        .onExitCommand {
            let handled = viewModel.handleMenuPress()
            if !handled {
                dismiss()
            }
        }
        .onChange(of: viewModel.showOverlay) { _, isVisible in
            if !isVisible && viewModel.errorMessage == nil {
                isPlayerFocused = true
                Task { @MainActor in
                    if !viewModel.showOverlay && viewModel.errorMessage == nil {
                        isPlayerFocused = true
                    }
                }
            }
        }
        .onChange(of: viewModel.isShowingChaptersSheet) { _, isPresented in
            if !isPresented {
                viewModel.resetInactivityTimer()
            }
        }
        .onChange(of: viewModel.isShowingTracksSheet) { _, isPresented in
            if !isPresented {
                viewModel.resetInactivityTimer()
            }
        }
        .sheet(isPresented: $viewModel.isShowingChaptersSheet) {
            TVVideoChaptersSheetView(
                chapters: viewModel.availableChapters,
                currentTime: viewModel.currentTime,
                duration: viewModel.duration,
                onSelectTime: { targetSeconds in
                    viewModel.jumpToTime(targetSeconds)
                }
            )
        }
        .sheet(isPresented: $viewModel.isShowingTracksSheet) {
            TVTracksMenuView(
                audioTracks: viewModel.availableAudioTracks,
                selectedAudio: viewModel.selectedAudioTrack,
                subtitleTracks: viewModel.availableSubtitleTracks,
                selectedSubtitle: viewModel.selectedSubtitleTrack,
                onSelectAudio: { track in
                    viewModel.selectAudioTrack(track)
                },
                onSelectSubtitle: { track in
                    viewModel.selectSubtitleTrack(track)
                }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            isPlayerFocused = true
            viewModel.loadCurrentVideo()
        }
        .onDisappear {
            viewModel.tearDown()
        }
    }
}
