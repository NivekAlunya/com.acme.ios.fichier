//
//  AirPlayButtonView.swift
//  fichier
//

import SwiftUI
import AVKit

public struct AirPlayButtonView: UIViewRepresentable {
    public var tintColor: UIColor
    public var activeTintColor: UIColor
    
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
