//
//  TVVideoSeekPreviewHUDView.swift
//  FichierTV
//
//

import FichierKit
import SwiftUI

/// Non-focusable floating seek preview HUD displayed during `<<`/`>>` remote taps and holds
/// so Focus Engine focus remains uninterrupted on `TVPlayerRemoteCatcherView`.
public struct TVVideoSeekPreviewHUDView: View {
    public let title: String
    public let duration: Double
    public let preview: TVRemoteSeekPreview
    public let chapters: [PlayerChapter]
    public let seekThumbnailState: TVSeekThumbnailState?

    public init(
        title: String,
        duration: Double,
        preview: TVRemoteSeekPreview,
        chapters: [PlayerChapter] = [],
        seekThumbnailState: TVSeekThumbnailState? = nil
    ) {
        self.title = title
        self.duration = duration
        self.preview = preview
        self.chapters = chapters
        self.seekThumbnailState = seekThumbnailState
    }

    private var formattedDelta: String {
        TVRemoteSeekCalculator.formattedDelta(preview.deltaSeconds)
    }

    private var formattedTargetTime: String {
        TVRemoteSeekCalculator.formattedTimestamp(preview.targetTime)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                if let seekThumbnailState {
                    TVSeekThumbnailPreviewCardView(
                        thumbnailState: seekThumbnailState,
                        duration: duration,
                        detailLabel: formattedDelta
                    )
                }

                HStack(spacing: 12) {
                    Text(title)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.white.opacity(0.85))

                    Spacer()

                    HStack(spacing: 10) {
                        Image(systemName: preview.isForward ? "forward.fill" : "backward.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)

                        Text("\(formattedDelta) • \(formattedTargetTime)")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.orange.opacity(0.65), lineWidth: 1.5)
                    )
                    .shadow(radius: 8)
                }

                TVVideoScrubberView(
                    currentTime: preview.targetTime,
                    duration: duration,
                    scrubbingTime: preview.targetTime,
                    isFocused: true,
                    chapters: chapters,
                    showsPreviewBubble: false
                )
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 50)
            .padding(.top, 36)
            .background(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Seek preview")
        .accessibilityValue("\(formattedDelta), \(formattedTargetTime)")
    }
}
