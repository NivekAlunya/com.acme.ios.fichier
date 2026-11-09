//
//  TVOverlayButtonStyle.swift
//  FichierTV
//

import SwiftUI

/// Custom tvOS button style for viewer overlay controls, providing scale and fill upon focus.
public struct TVOverlayButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isFocused ? Color.white : Color.black.opacity(0.45))
            )
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .opacity(isEnabled ? 1.0 : 0.45)
            .scaleEffect(isFocused && !reduceMotion ? 1.12 : 1.0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isFocused)
            .shadow(color: isFocused ? Color.white.opacity(0.3) : Color.clear, radius: 10, y: 4)
    }
}
