//
//  TVMediaCardButtonStyle.swift
//  FichierTV
//
//

import SwiftUI

/// Focus-reactive button style for tvOS portrait media cards without system card corner clipping.
public struct TVMediaCardButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        TVMediaCardButtonContent(configuration: configuration)
    }
}

private struct TVMediaCardButtonContent: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.05 : 1.0))
            .shadow(
                color: isFocused ? Color.black.opacity(0.45) : Color.clear,
                radius: isFocused ? 18 : 0,
                x: 0,
                y: isFocused ? 10 : 0
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
