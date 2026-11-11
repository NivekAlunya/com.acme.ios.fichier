//
//  VideoTimelineBar.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Custom interactive timeline scrubber bar component for video playback.
///
/// Features:
/// - Monospaced elapsed time label on the leading edge.
/// - Dynamic progress track with interactive dragging knob that enlarges (10pt to 16pt) when scrubbed,
///   plus chapter tick marks along the timeline track.
/// - Trailing time button toggling between remaining time (`-0:42`) and total duration (`2:15`).
/// - Full VoiceOver accessibility with adjustable increment/decrement actions.
public struct VideoTimelineBar: View {
    /// Current playback progress in seconds.
    public let currentTime: Double
    
    /// Total duration of the video in seconds.
    public let duration: Double
    
    /// Chapter markers rendered as tick indicators along the progress bar.
    public let chapters: [PlayerChapter]
    
    /// Accent tint color for elapsed progress and active seek knob.
    public let tintColor: Color
    
    /// Final seek commit callback invoked upon releasing the scrubber drag gesture.
    public let onSeek: (Double) -> Void
    
    /// Continuous scrubbing callback invoked as the user drags their finger across the track.
    public let onScrubbing: ((Double) -> Void)?
    
    /// Callback signaling changes in active scrubbing state.
    public let onScrubStateChanged: (Bool) -> Void
    
    @State private var isScrubbing: Bool = false
    @State private var scrubTargetTime: Double = 0
    @State private var showRemainingTime: Bool = true
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - currentTime: Current playback progress in seconds.
    ///   - duration: Total duration in seconds.
    ///   - chapters: Chapter markers along the timeline.
    ///   - tintColor: Accent tint color for elapsed progress (defaults to `.blue`).
    ///   - onSeek: Commit seek handler.
    ///   - onScrubbing: Real-time scrub movement handler.
    ///   - onScrubStateChanged: Scrub state transition handler.
    public init(
        currentTime: Double,
        duration: Double,
        chapters: [PlayerChapter] = [],
        tintColor: Color = .blue,
        onSeek: @escaping (Double) -> Void,
        onScrubbing: ((Double) -> Void)? = nil,
        onScrubStateChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.currentTime = currentTime
        self.duration = duration
        self.chapters = chapters
        self.tintColor = tintColor
        self.onSeek = onSeek
        self.onScrubbing = onScrubbing
        self.onScrubStateChanged = onScrubStateChanged
    }
    
    /// Effective timestamp currently driving UI display (reflects scrub target during dragging).
    private var effectiveCurrentTime: Double {
        isScrubbing ? scrubTargetTime : currentTime
    }
    
    /// Normalized progress fraction between `0.0` and `1.0`.
    private var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return max(0.0, min(1.0, effectiveCurrentTime / duration))
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // Elapsed Time
            Text(formatSeconds(effectiveCurrentTime))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .frame(minWidth: 42, alignment: .leading)
            
            // Ultra-Smooth Interactive Progress Slider
            GeometryReader { geo in
                let width = geo.size.width
                let fraction = progressFraction
                let knobSize: CGFloat = isScrubbing ? 16 : 10
                let knobRadius: CGFloat = knobSize / 2
                let maxOffset = max(0, width - knobSize)
                
                ZStack(alignment: .leading) {
                    // Track Background
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(height: isScrubbing ? 6 : 4)
                    
                    // Active Played Progress
                    Capsule()
                        .fill(tintColor)
                        .frame(width: max(0, width * CGFloat(fraction)), height: isScrubbing ? 6 : 4)
                    
                    // Chapter Tick Marks
                    if duration > 0 && !chapters.isEmpty {
                        ForEach(chapters) { chapter in
                            if chapter.startTime > 0 && chapter.startTime < duration {
                                let tickX = width * CGFloat(chapter.startTime / duration)
                                Rectangle()
                                    .fill(Color.black.opacity(0.65))
                                    .frame(width: 2, height: isScrubbing ? 6 : 4)
                                    .offset(x: tickX - 1)
                            }
                        }
                    }
                    
                    // Scrubber Knob
                    Circle()
                        .fill(Color.white)
                        .frame(width: knobSize, height: knobSize)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                        .offset(x: max(0, min(maxOffset, width * CGFloat(fraction) - knobRadius)))
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                #if !os(tvOS)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard width > 0, duration > 0 else { return }
                            if !isScrubbing {
                                isScrubbing = true
                                onScrubStateChanged(true)
                            }
                            let newFraction = max(0.0, min(1.0, Double(value.location.x / width)))
                            scrubTargetTime = newFraction * duration
                            onScrubbing?(scrubTargetTime)
                        }
                        .onEnded { value in
                            guard width > 0, duration > 0 else {
                                if isScrubbing {
                                    isScrubbing = false
                                    onScrubStateChanged(false)
                                }
                                return
                            }
                            let newFraction = max(0.0, min(1.0, Double(value.location.x / width)))
                            let finalTime = newFraction * duration
                            // Commit seek once when user releases finger
                            isScrubbing = false
                            onScrubStateChanged(false)
                            onSeek(finalTime)
                        }
                )
                #endif
            }
            .frame(height: 36)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Playback Timeline", comment: "Accessibility label for playback scrubber"))
            .accessibilityValue("\(formatSeconds(effectiveCurrentTime)) of \(formatSeconds(duration))")
            .accessibilityAdjustableAction { direction in
                guard duration > 0 else { return }
                let delta = max(5.0, duration * 0.05)
                switch direction {
                case .increment:
                    let target = min(duration, effectiveCurrentTime + delta)
                    onSeek(target)
                case .decrement:
                    let target = max(0, effectiveCurrentTime - delta)
                    onSeek(target)
                @unknown default:
                    break
                }
            }
            
            // Duration / Remaining Time (Tap to toggle)
            Button {
                showRemainingTime.toggle()
            } label: {
                Text(rightTimeLabel)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(minWidth: 48, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showRemainingTime ? String(localized: "Remaining time, tap to show total duration", comment: "Accessibility label for remaining time button") : String(localized: "Total duration, tap to show remaining time", comment: "Accessibility label for total duration button"))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
    
    /// Formats the trailing time string based on toggle preference.
    private var rightTimeLabel: String {
        guard duration > 0 else { return "0:00" }
        if showRemainingTime {
            let remaining = max(0, duration - effectiveCurrentTime)
            return "-\(formatSeconds(remaining))"
        } else {
            return formatSeconds(duration)
        }
    }
    
    /// Formats a time in seconds into a digital clock string.
    private func formatSeconds(_ totalSeconds: Double) -> String {
        guard totalSeconds.isFinite && !totalSeconds.isNaN && totalSeconds >= 0 else { return "0:00" }
        let secs = Int(totalSeconds)
        let hours = secs / 3600
        let minutes = (secs % 3600) / 60
        let seconds = secs % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
