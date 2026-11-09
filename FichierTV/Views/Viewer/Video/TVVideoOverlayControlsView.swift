//
//  TVVideoOverlayControlsView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Two-row tvOS video player HUD overlay with focusable scrubber bar and playback buttons.
public struct TVVideoOverlayControlsView: View {
    public let title: String
    public let currentTime: Double
    public let duration: Double
    public let isPlaying: Bool
    public let isScrubbing: Bool
    public let scrubbingTime: Double?
    public let chapters: [PlayerChapter]
    public let seekThumbnailState: TVSeekThumbnailState?
    public let remoteSeekPreview: TVRemoteSeekPreview?
    public let isChaptersSheetPresented: Bool
    public let isTracksSheetPresented: Bool
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
    public let onOpenChapters: () -> Void
    public let onOpenTracks: () -> Void

    @FocusState private var focusedTarget: TVVideoOverlayFocusTarget?

    public init(
        title: String,
        currentTime: Double,
        duration: Double,
        isPlaying: Bool,
        isScrubbing: Bool,
        scrubbingTime: Double?,
        chapters: [PlayerChapter] = [],
        seekThumbnailState: TVSeekThumbnailState? = nil,
        remoteSeekPreview: TVRemoteSeekPreview? = nil,
        isChaptersSheetPresented: Bool = false,
        isTracksSheetPresented: Bool,
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
        onOpenChapters: @escaping () -> Void = {},
        onOpenTracks: @escaping () -> Void
    ) {
        self.title = title
        self.currentTime = currentTime
        self.duration = duration
        self.isPlaying = isPlaying
        self.isScrubbing = isScrubbing
        self.scrubbingTime = scrubbingTime
        self.chapters = chapters
        self.seekThumbnailState = seekThumbnailState
        self.remoteSeekPreview = remoteSeekPreview
        self.isChaptersSheetPresented = isChaptersSheetPresented
        self.isTracksSheetPresented = isTracksSheetPresented
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
        self.onOpenChapters = onOpenChapters
        self.onOpenTracks = onOpenTracks
    }

    public var body: some View {
        ZStack {
            TVOverlayPanCaptureView(
                isEnabled: focusedTarget == .progress && !isTracksSheetPresented && !isChaptersSheetPresented,
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
        HStack {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white)

            Spacer()
        }
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
        HStack(spacing: 32) {
            Button(action: onPrevious) {
                Label("Previous", systemImage: "backward.end.fill")
            }
            .buttonStyle(TVOverlayButtonStyle())
            .focused($focusedTarget, equals: .previous)
            .accessibilityLabel("Previous video")
            .accessibilityIdentifier("video_previous_button")

            Button(action: onTogglePlayPause) {
                Label(
                    isPlaying ? "Pause" : "Play",
                    systemImage: isPlaying ? "pause.fill" : "play.fill"
                )
            }
            .buttonStyle(TVOverlayButtonStyle())
            .focused($focusedTarget, equals: .playPause)
            .accessibilityLabel(isPlaying ? "Pause video" : "Play video")
            .accessibilityIdentifier("video_play_pause_button")

            Button(action: onNext) {
                Label("Next", systemImage: "forward.end.fill")
            }
            .buttonStyle(TVOverlayButtonStyle())
            .focused($focusedTarget, equals: .next)
            .accessibilityLabel("Next video")
            .accessibilityIdentifier("video_next_button")

            Button(action: onOpenChapters) {
                Label(
                    chapters.isEmpty ? "Jump" : "Chapters",
                    systemImage: chapters.isEmpty ? "forward.frame.fill" : "list.bullet.rectangle.fill"
                )
            }
            .buttonStyle(TVOverlayButtonStyle())
            .focused($focusedTarget, equals: .chapters)
            .accessibilityLabel("Chapters and quick jump")
            .accessibilityIdentifier("video_chapters_button")

            Button(action: onOpenTracks) {
                Label("Tracks", systemImage: "captions.bubble.fill")
            }
            .buttonStyle(TVOverlayButtonStyle())
            .focused($focusedTarget, equals: .tracks)
            .accessibilityLabel("Audio and subtitle tracks")
            .accessibilityIdentifier("video_tracks_button")
        }
    }
}
