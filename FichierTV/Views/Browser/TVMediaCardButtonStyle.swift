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
