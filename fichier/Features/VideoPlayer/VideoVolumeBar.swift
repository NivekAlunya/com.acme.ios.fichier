//
//  VideoVolumeBar.swift
//  fichier
//

import SwiftUI

public struct VideoVolumeBar: View {
    @Binding public var volume: Double
    @Binding public var isMuted: Bool
    
    public init(volume: Binding<Double>, isMuted: Binding<Bool>) {
        self._volume = volume
        self._isMuted = isMuted
    }
    
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
        .background(Capsule().fill(.ultraThinMaterial))
    }
}
