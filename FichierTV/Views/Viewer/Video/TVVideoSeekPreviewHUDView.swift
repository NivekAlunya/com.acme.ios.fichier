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
    public let engineKind: PlayerEngineKind
    public let duration: Double
    public let preview: TVRemoteSeekPreview
    public let chapters: [PlayerChapter]
    public let seekThumbnailState: TVSeekThumbnailState?

    public init(
        title: String,
        engineKind: PlayerEngineKind = .native,
        duration: Double,
        preview: TVRemoteSeekPreview,
        chapters: [PlayerChapter] = [],
        seekThumbnailState: TVSeekThumbnailState? = nil
    ) {
        self.title = title
        self.engineKind = engineKind
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
                TVVideoScrubberView(
                    currentTime: preview.targetTime,
                    duration: duration,
                    scrubbingTime: preview.targetTime,
                    isFocused: true,
                    tintColor: engineKind == .extended ? .orange : .blue,
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
