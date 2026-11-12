//
//  TVOverlayButtonStyle.swift
//  FichierTV
//

import SwiftUI

/// Custom tvOS button style for viewer overlay controls, providing scale and fill upon focus.
public struct TVOverlayButtonStyle: ButtonStyle {
    public let focusedFillColor: Color
    public let focusedForegroundColor: Color
    public let font: Font

    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        focusedFillColor: Color = .white,
        focusedForegroundColor: Color = .black,
        font: Font = .headline
    ) {
        self.focusedFillColor = focusedFillColor
        self.focusedForegroundColor = focusedForegroundColor
        self.font = font
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isFocused ? focusedFillColor : Color.black.opacity(0.45))
            )
            .foregroundStyle(isFocused ? focusedForegroundColor : Color.white)
            .opacity(isEnabled ? 1.0 : 0.45)
            .scaleEffect(isFocused && !reduceMotion ? 1.12 : 1.0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isFocused)
            .shadow(color: isFocused ? focusedFillColor.opacity(0.4) : Color.clear, radius: 10, y: 4)
    }
}
