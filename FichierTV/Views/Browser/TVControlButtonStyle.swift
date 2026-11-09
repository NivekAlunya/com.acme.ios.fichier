//
//  TVControlButtonStyle.swift
//  FichierTV
//

import SwiftUI

/// Focusable pill button style for tvOS browser toolbar controls (`Grid`, `List`, `Sort`).
///
/// Preserves SwiftUI view identity when selection toggles while clearly distinguishing
/// focused, active-selected, and idle states at 10-foot viewing distance.
public struct TVControlButtonStyle: ButtonStyle {
    public let isSelected: Bool

    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isSelected: Bool = false) {
        self.isSelected = isSelected
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected && !isFocused ? 2 : 0)
            )
            .foregroundStyle(foregroundColor)
            .scaleEffect(scaleAmount(isPressed: configuration.isPressed))
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isFocused)
            .shadow(color: isFocused ? Color.white.opacity(0.32) : Color.clear, radius: 12, y: 4)
    }

    private var backgroundColor: Color {
        if isFocused {
            return .white
        }
        if isSelected {
            return Color(red: 0.06, green: 0.45, blue: 0.95)
        }
        return Color.white.opacity(0.14)
    }

    private var foregroundColor: Color {
        if isFocused {
            return .black
        }
        return .white
    }

    private var borderColor: Color {
        isSelected && !isFocused ? Color.white.opacity(0.35) : .clear
    }

    private func scaleAmount(isPressed: Bool) -> CGFloat {
        if reduceMotion {
            return 1.0
        }
        if isPressed {
            return 0.98
        }
        return isFocused ? 1.06 : 1.0
    }
}
