//
//  TVPlayerCanvasView.swift
//  FichierTV
//

import SwiftUI
import AVFoundation

/// Custom `UIViewRepresentable` hosting `AVPlayerLayer` for control-less video rendering on tvOS.
///
/// NOTE: UIKit view is utilized here because SwiftUI on tvOS does not provide an equivalent API
/// to attach an `AVPlayer` without embedding system transport controls.
public struct TVPlayerCanvasView: UIViewRepresentable {
    public let player: AVPlayer

    public init(player: AVPlayer) {
        self.player = player
    }

    public func makeUIView(context: Context) -> TVPlayerContainerUIView {
        let view = TVPlayerContainerUIView(frame: .zero)
        view.playerLayer.player = player
        return view
    }

    public func updateUIView(_ uiView: TVPlayerContainerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}
