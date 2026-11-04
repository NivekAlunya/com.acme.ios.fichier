//
//  VideoVolumeBar.swift
//  fichier
//

import SwiftUI

/// Compact volume slider control with speaker status icon and interactive drag track.
///
/// Features:
/// - Dynamic speaker icon transitioning from muted slash to 1, 2, or 3 sound waves based on volume level.
/// - Tap speaker icon to toggle mute state.
/// - Drag slider track to continuously scale volume between `0.0` and `1.0`.
/// - Full VoiceOver accessibility with percentage reporting and adjustable increment/decrement actions.
public struct VideoVolumeBar: View {
    /// Two-way binding for normalized volume level (0.0 to 1.0).
    @Binding public var volume: Double
    
    /// Two-way binding for muted boolean state.
    @Binding public var isMuted: Bool
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - volume: Volume level binding.
    ///   - isMuted: Muted state binding.
    public init(volume: Binding<Double>, isMuted: Binding<Bool>) {
        self._volume = volume
        self._isMuted = isMuted
    }
    
    /// SF Symbol icon name reflecting current volume percentage and mute status.
    private var speakerIconName: String {
        if isMuted || volume <= 0.001 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isMuted.toggle()
                }
            } label: {
                Image(systemName: speakerIconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isMuted ? .red : .white)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMuted ? String(localized: "Unmute", comment: "Accessibility label to unmute volume") : String(localized: "Mute", comment: "Accessibility label to mute volume"))
            
            GeometryReader { geo in
                let trackWidth = geo.size.width
                let currentFraction = isMuted ? 0.0 : max(0.0, min(1.0, volume))
                
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(height: 5)
                    
                    Capsule()
                        .fill(isMuted ? Color.gray : Color.white)
                        .frame(width: trackWidth * currentFraction, height: 5)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0.0, min(1.0, value.location.x / trackWidth))
                            if isMuted && fraction > 0 {
                                isMuted = false
                            }
                            volume = fraction
                        }
                )
            }
            .frame(width: 60, height: 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Volume", comment: "Accessibility label for volume slider"))
            .accessibilityValue("\(Int(volume * 100))%")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    let newVol = min(1.0, volume + 0.1)
                    if isMuted { isMuted = false }
                    volume = newVol
                case .decrement:
                    volume = max(0.0, volume - 0.1)
                @unknown default:
                    break
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        )
    }
}
