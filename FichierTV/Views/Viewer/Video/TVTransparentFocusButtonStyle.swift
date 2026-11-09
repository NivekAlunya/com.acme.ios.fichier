//
//  TVTransparentFocusButtonStyle.swift
//  FichierTV
//
//

import SwiftUI

/// Borderless, chrome-free tvOS button style for focusable overlay triggers and scrubber controls.
public struct TVTransparentFocusButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
