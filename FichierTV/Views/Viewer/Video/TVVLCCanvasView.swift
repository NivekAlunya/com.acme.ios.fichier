//
//  TVVLCCanvasView.swift
//  FichierTV
//
//

import SwiftUI
import FichierKit

/// Custom `UIViewRepresentable` hosting `TVVLCPlayerEngine`'s drawable surface for extended codecs (MKV, AVI, WebM, etc.).
///
/// NOTE: UIKit view is utilized here because SwiftUI on tvOS does not provide an equivalent API
/// for attaching a `VLCMediaPlayer.drawable` video output surface.
public struct TVVLCCanvasView: UIViewRepresentable {
    public let engine: TVVLCPlayerEngine

    public init(engine: TVVLCPlayerEngine) {
        self.engine = engine
    }

    public func makeUIView(context: Context) -> TVVLCRenderUIView {
        let container = TVVLCRenderUIView(frame: .zero)
        container.mountRenderView(engine.renderView)
        engine.attachDrawable()
        return container
    }

    public func updateUIView(_ uiView: TVVLCRenderUIView, context: Context) {
        uiView.mountRenderView(engine.renderView)
        engine.attachDrawable()
    }
}
