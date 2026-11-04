//
//  AirPlayButtonView.swift
//  fichier
//

import SwiftUI
import AVKit

/// SwiftUI bridge wrapping AVKit's `AVRoutePickerView` for wireless AirPlay audio and video streaming.
///
/// Sets `prioritizesVideoDevices = true` to display external television and Apple TV targets prominently.
public struct AirPlayButtonView: UIViewRepresentable {
    /// Inactive icon tint color.
    public var tintColor: UIColor
    
    /// Active route picker icon tint color when an AirPlay route is connected.
    public var activeTintColor: UIColor
    
    /// Memberwise designated initializer.
    ///
    /// - Parameters:
    ///   - tintColor: Inactive tint color (defaults to `.white`).
    ///   - activeTintColor: Active route tint color (defaults to `.systemBlue`).
    public init(
        tintColor: UIColor = .white,
        activeTintColor: UIColor = .systemBlue
    ) {
        self.tintColor = tintColor
        self.activeTintColor = activeTintColor
    }
    
    public func makeUIView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView()
        routePicker.tintColor = tintColor
        routePicker.activeTintColor = activeTintColor
        routePicker.backgroundColor = .clear
        routePicker.prioritizesVideoDevices = true
        return routePicker
    }
    
    public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
        uiView.activeTintColor = activeTintColor
    }
}
