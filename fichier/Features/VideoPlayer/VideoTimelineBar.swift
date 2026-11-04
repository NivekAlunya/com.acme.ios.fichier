//
//  VideoTimelineBar.swift
//  fichier
//

import SwiftUI

public struct VideoTimelineBar: View {
    public let currentTime: Double
    public let duration: Double
    public let onSeek: (Double) -> Void
    public let onScrubbing: ((Double) -> Void)?
    public let onScrubStateChanged: (Bool) -> Void
    
    @State private var isScrubbing: Bool = false
    @State private var scrubTargetTime: Double = 0
    @State private var showRemainingTime: Bool = true
    
    public init(
        currentTime: Double,
        duration: Double,
        onSeek: @escaping (Double) -> Void,
        onScrubbing: ((Double) -> Void)? = nil,
        onScrubStateChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.currentTime = currentTime
        self.duration = duration
        self.onSeek = onSeek
        self.onScrubbing = onScrubbing
        self.onScrubStateChanged = onScrubStateChanged
    }
    
    private var effectiveCurrentTime: Double {
        isScrubbing ? scrubTargetTime : currentTime
    }
    
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
                        .fill(Color.white)
                        .frame(width: max(0, width * CGFloat(fraction)), height: isScrubbing ? 6 : 4)
                    
                    // Scrubber Knob
                    Circle()
                        .fill(Color.white)
                        .frame(width: knobSize, height: knobSize)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                        .offset(x: max(0, min(maxOffset, width * CGFloat(fraction) - knobRadius)))
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
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
    
    private var rightTimeLabel: String {
        guard duration > 0 else { return "0:00" }
        if showRemainingTime {
            let remaining = max(0, duration - effectiveCurrentTime)
            return "-\(formatSeconds(remaining))"
        } else {
            return formatSeconds(duration)
        }
    }
    
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
