//
//  TVVideoScrubberView.swift
//  FichierTV
//

import FichierKit
import SwiftUI

/// Progress bar row providing live playback indicator, chapter tick markers, and accelerated Siri Remote scrubbing with live thumbnail preview.
public struct TVVideoScrubberView: View {
    public let currentTime: Double
    public let duration: Double
    public let scrubbingTime: Double?
    public let isFocused: Bool
    public let chapters: [PlayerChapter]
    public let seekThumbnailState: TVSeekThumbnailState?
    public let previewBubbleLabel: String?
    public let showsPreviewBubble: Bool

    public init(
        currentTime: Double,
        duration: Double,
        scrubbingTime: Double?,
        isFocused: Bool,
        chapters: [PlayerChapter] = [],
        seekThumbnailState: TVSeekThumbnailState? = nil,
        previewBubbleLabel: String? = nil,
        showsPreviewBubble: Bool = true
    ) {
        self.currentTime = currentTime
        self.duration = duration
        self.scrubbingTime = scrubbingTime
        self.isFocused = isFocused
        self.chapters = chapters
        self.seekThumbnailState = seekThumbnailState
        self.previewBubbleLabel = previewBubbleLabel
        self.showsPreviewBubble = showsPreviewBubble
    }

    private var displayTime: Double {
        scrubbingTime ?? currentTime
    }

    private var progressRatio: Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, displayTime / duration))
    }

    public var body: some View {
        VStack(spacing: 8) {
            if showsPreviewBubble, let scrubbingTime {
                if let seekThumbnailState {
                    TVSeekThumbnailPreviewCardView(
                        thumbnailState: seekThumbnailState,
                        duration: duration,
                        detailLabel: previewBubbleLabel ?? "Click to seek"
                    )
                } else {
                    previewTimestampBubble(time: scrubbingTime)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(height: isFocused ? 14 : 8)

                    if duration > 0 {
                        ForEach(chapters) { chapter in
                            if chapter.startTime > 0 && chapter.startTime < duration {
                                let ratio = chapter.startTime / duration
                                Rectangle()
                                    .fill(Color.white.opacity(0.65))
                                    .frame(width: 2, height: isFocused ? 14 : 8)
                                    .offset(x: max(0, min(proxy.size.width - 2, proxy.size.width * ratio - 1)))
                            }
                        }
                    }

                    Capsule()
                        .fill(scrubbingTime != nil ? Color.orange : Color.white)
                        .frame(width: proxy.size.width * progressRatio, height: isFocused ? 14 : 8)

                    if isFocused || scrubbingTime != nil {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .shadow(radius: 4)
                            .offset(x: max(0, min(proxy.size.width - 22, proxy.size.width * progressRatio - 11)))
                    }
                }
            }
            .frame(height: isFocused ? 22 : 12)
            .animation(.snappy(duration: 0.15), value: isFocused)

            HStack {
                Text(formatTimestamp(displayTime))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(scrubbingTime != nil ? .orange : .white)

                Spacer()

                Text(formatTimestamp(duration))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isFocused ? Color.white.opacity(0.15) : Color.clear)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback progress")
        .accessibilityValue("\(formatTimestamp(displayTime)) of \(formatTimestamp(duration))")
    }

    @ViewBuilder
    private func previewTimestampBubble(time: Double) -> some View {
        Text(previewBubbleLabel ?? "Scrub: \(formatTimestamp(time))")
            .font(.caption.weight(.bold).monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.orange)
            .shadow(radius: 6)
    }

    private func formatTimestamp(_ totalSeconds: Double) -> String {
        TVRemoteSeekCalculator.formattedTimestamp(totalSeconds)
    }
}
