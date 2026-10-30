//
//  VideoProgressRing.swift
//  fichier
//

import SwiftUI

public struct VideoProgressRing: View {
    public let progress: Double
    public var size: CGFloat
    public var lineWidth: CGFloat
    public var ringColor: Color
    
    public init(
        progress: Double,
        size: CGFloat = 9.0,
        lineWidth: CGFloat = 1.5,
        ringColor: Color = .blue
    ) {
        self.progress = max(0.0, min(1.0, progress))
        self.size = size
        self.lineWidth = lineWidth
        self.ringColor = ringColor
    }
    
    public var body: some View {
        ZStack {
            // Subtle background track
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: lineWidth)
            
            // Progress arc
            Circle()
                .trim(from: 0.0, to: CGFloat(max(0.05, progress)))
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}
