//
//  TVVideoOverlayControlsView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Two-row tvOS video player HUD overlay with focusable scrubber bar and playback buttons.
public struct TVVideoOverlayControlsView: View {
    public let title: String
    public let engineKind: PlayerEngineKind
    public let currentTime: Double
    public let duration: Double
    public let isPlaying: Bool
    public let isScrubbing: Bool
    public let scrubbingTime: Double?
    public let chapters: [PlayerChapter]
    public let seekThumbnailState: TVSeekThumbnailState?
    public let remoteSeekPreview: TVRemoteSeekPreview?
    public let playbackRate: TVVideoPlaybackRate
    public let isChaptersSheetPresented: Bool
    public let isTracksSheetPresented: Bool
    public let isSpeedSheetPresented: Bool
    public let initialFocusTarget: TVVideoOverlayFocusTarget
    public let onFocusChanged: (TVVideoOverlayFocusTarget?) -> Void
    public let onScrubStep: (Bool) -> Void
    public let onSwipeScrubChanged: @MainActor (_ deltaX: CGFloat, _ velocityX: CGFloat, _ trackWidth: CGFloat) -> Void
    public let onSwipeScrubEnded: @MainActor () -> Void
    public let onSwipeScrubCancelled: @MainActor () -> Void
    public let onScrubberSelect: () -> Void
    public let onPrevious: () -> Void
    public let onTogglePlayPause: () -> Void
    public let onNext: () -> Void
    public let onSwitchEngine: () -> Void
    public let onOpenChapters: () -> Void
    public let onOpenTracks: () -> Void
    public let onOpenSpeed: () -> Void

    @FocusState private var focusedTarget: TVVideoOverlayFocusTarget?

    public init(
        title: String,
        engineKind: PlayerEngineKind = .native,
        currentTime: Double,
        duration: Double,
        isPlaying: Bool,
        isScrubbing: Bool,
        scrubbingTime: Double?,
        chapters: [PlayerChapter] = [],
        seekThumbnailState: TVSeekThumbnailState? = nil,
        remoteSeekPreview: TVRemoteSeekPreview? = nil,
        playbackRate: TVVideoPlaybackRate = .normal,
        isChaptersSheetPresented: Bool = false,
        isTracksSheetPresented: Bool,
        isSpeedSheetPresented: Bool = false,
        initialFocusTarget: TVVideoOverlayFocusTarget = .playPause,
        onFocusChanged: @escaping (TVVideoOverlayFocusTarget?) -> Void,
        onScrubStep: @escaping (Bool) -> Void,
        onSwipeScrubChanged: @escaping @MainActor (_ deltaX: CGFloat, _ velocityX: CGFloat, _ trackWidth: CGFloat) -> Void = { _, _, _ in },
        onSwipeScrubEnded: @escaping @MainActor () -> Void = {},
        onSwipeScrubCancelled: @escaping @MainActor () -> Void = {},
        onScrubberSelect: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onTogglePlayPause: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onSwitchEngine: @escaping () -> Void = {},
        onOpenChapters: @escaping () -> Void = {},
        onOpenTracks: @escaping () -> Void,
        onOpenSpeed: @escaping () -> Void = {}
    ) {
        self.title = title
        self.engineKind = engineKind
        self.currentTime = currentTime
        self.duration = duration
        self.isPlaying = isPlaying
        self.isScrubbing = isScrubbing
        self.scrubbingTime = scrubbingTime
        self.chapters = chapters
        self.seekThumbnailState = seekThumbnailState
        self.remoteSeekPreview = remoteSeekPreview
        self.playbackRate = playbackRate
        self.isChaptersSheetPresented = isChaptersSheetPresented
        self.isTracksSheetPresented = isTracksSheetPresented
        self.isSpeedSheetPresented = isSpeedSheetPresented
        self.initialFocusTarget = initialFocusTarget
        self.onFocusChanged = onFocusChanged
        self.onScrubStep = onScrubStep
        self.onSwipeScrubChanged = onSwipeScrubChanged
        self.onSwipeScrubEnded = onSwipeScrubEnded
        self.onSwipeScrubCancelled = onSwipeScrubCancelled
        self.onScrubberSelect = onScrubberSelect
        self.onPrevious = onPrevious
        self.onTogglePlayPause = onTogglePlayPause
        self.onNext = onNext
        self.onSwitchEngine = onSwitchEngine
        self.onOpenChapters = onOpenChapters
        self.onOpenTracks = onOpenTracks
        self.onOpenSpeed = onOpenSpeed
    }

    public var body: some View {
        ZStack {
            TVOverlayPanCaptureView(
                isEnabled: focusedTarget == .progress && !isTracksSheetPresented && !isChaptersSheetPresented && !isSpeedSheetPresented,
                onPanChanged: onSwipeScrubChanged,
                onPanEnded: onSwipeScrubEnded,
                onPanCancelled: onSwipeScrubCancelled
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 60)
                    .padding(.top, 40)

                Spacer()

                VStack(spacing: 24) {
                    // Row 1: Progress Scrubber
                    progressRow
                        .focusSection()

                    // Row 2: Control Buttons
                    buttonsRow
                        .frame(maxWidth: .infinity)
                        .focusSection()
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($focusedTarget, initialFocusTarget)
        .onAppear {
            focusedTarget = initialFocusTarget
            Task { @MainActor in
                if focusedTarget == nil {
                    focusedTarget = initialFocusTarget
                }
            }
        }
        .onChange(of: focusedTarget) { _, newValue in
            onFocusChanged(newValue)
        }
        .onChange(of: isChaptersSheetPresented) { _, isPresented in
            if !isPresented && focusedTarget == nil {
                focusedTarget = .chapters
            }
        }
        .onChange(of: isTracksSheetPresented) { _, isPresented in
            if !isPresented && focusedTarget == nil {
                focusedTarget = .tracks
            }
        }
        .onChange(of: isSpeedSheetPresented) { _, isPresented in
            if !isPresented && focusedTarget == nil {
                focusedTarget = .speed
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.7),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white)

            #if DEBUG
            let isVLC = engineKind == .extended
            Text(isVLC ? "VLC" : "NATIVE")
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill((isVLC ? Color.orange : Color.blue).opacity(0.85))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                        )
                )
                .accessibilityIdentifier("tv_video_player_debug_engine_badge")
            #endif

            Spacer()
        }
    }

    private var engineTintColor: Color {
        engineKind == .extended ? .orange : .blue
    }

    @ViewBuilder
    private var progressRow: some View {
        let effectiveScrubTime = scrubbingTime ?? remoteSeekPreview?.targetTime
        let remotePreviewLabel: String? = if scrubbingTime == nil, let preview = remoteSeekPreview {
            TVRemoteSeekCalculator.formattedDelta(preview.deltaSeconds)
        } else {
            nil
        }

        Button {
            onScrubberSelect()
        } label: {
            TVVideoScrubberView(
                currentTime: currentTime,
                duration: duration,
                scrubbingTime: effectiveScrubTime,
                isFocused: focusedTarget == .progress,
                tintColor: engineTintColor,
                chapters: chapters,
                seekThumbnailState: seekThumbnailState,
                previewBubbleLabel: remotePreviewLabel
            )
        }
        .buttonStyle(TVTransparentFocusButtonStyle())
        .focused($focusedTarget, equals: .progress)
        .onMoveCommand { direction in
            switch direction {
            case .left:
                onScrubStep(false)
            case .right:
                onScrubStep(true)
            case .down:
                focusedTarget = .playPause
            default:
                onFocusChanged(.progress)
            }
        }
        .accessibilityLabel("Playback progress")
        .accessibilityIdentifier("video_scrubber_button")
    }

    @ViewBuilder
    private var buttonsRow: some View {
        let buttonStyle = TVOverlayButtonStyle(
            focusedFillColor: engineTintColor,
            focusedForegroundColor: .white,
            font: .subheadline
        )

        HStack(spacing: 24) {
            Button(action: onPrevious) {
                Label("Previous", systemImage: "backward.end.fill")
            }
            .buttonStyle(buttonStyle)
            .focused($focusedTarget, equals: .previous)
            .accessibilityLabel("Previous video")
            .accessibilityIdentifier("video_previous_button")

            Button(action: onTogglePlayPause) {
                Label(
                    isPlaying ? "Pause" : "Play",
                    systemImage: isPlaying ? "pause.fill" : "play.fill"
                )
            }
            .buttonStyle(buttonStyle)
            .focused($focusedTarget, equals: .playPause)
            .accessibilityLabel(isPlaying ? "Pause video" : "Play video")
            .accessibilityIdentifier("video_play_pause_button")

            Button(action: onNext) {
                Label("Next", systemImage: "forward.end.fill")
            }
            .buttonStyle(buttonStyle)
            .focused($focusedTarget, equals: .next)
            .accessibilityLabel("Next video")
            .accessibilityIdentifier("video_next_button")

            Button(action: onOpenChapters) {
                Label(
                    chapters.isEmpty ? "Jump" : "Chapters",
                    systemImage: chapters.isEmpty ? "forward.frame.fill" : "list.bullet.rectangle.fill"
                )
            }
            .buttonStyle(buttonStyle)
            .focused($focusedTarget, equals: .chapters)
            .accessibilityLabel("Chapters and quick jump")
            .accessibilityIdentifier("video_chapters_button")

            Button(action: onOpenTracks) {
                Label("Tracks", systemImage: "captions.bubble.fill")
            }
            .buttonStyle(buttonStyle)
            .focused($focusedTarget, equals: .tracks)
            .accessibilityLabel("Audio and subtitle tracks")
            .accessibilityIdentifier("video_tracks_button")

            Button(action: onOpenSpeed) {
                Label(
                    playbackRate == .normal ? "Speed" : playbackRate.displayName,
                    systemImage: "speedometer"
                )
            }
            .buttonStyle(buttonStyle)
            .focused($focusedTarget, equals: .speed)
            .accessibilityLabel("Playback speed \(playbackRate.displayName)")
            .accessibilityIdentifier("video_speed_button")

            Button(action: onSwitchEngine) {
                Label(
                    engineKind == .extended ? "AV" : "VLC",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(buttonStyle)
            .focused($focusedTarget, equals: .switchEngine)
            .accessibilityLabel(engineKind == .extended ? "Switch to Native Player" : "Switch to VLC Player")
            .accessibilityIdentifier("video_switch_engine_button")
        }
    }
}
