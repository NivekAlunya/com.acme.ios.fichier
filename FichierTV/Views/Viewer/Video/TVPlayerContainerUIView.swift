//
//  TVPlayerContainerUIView.swift
//  FichierTV
//

import UIKit
import AVFoundation

/// `UIView` backed directly by `AVPlayerLayer` so video bounds scale automatically with SwiftUI layout.
public final class TVPlayerContainerUIView: UIView {
    public override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    public var playerLayer: AVPlayerLayer {
        // Safe cast guaranteed by `layerClass` override.
        layer as! AVPlayerLayer
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        playerLayer.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
