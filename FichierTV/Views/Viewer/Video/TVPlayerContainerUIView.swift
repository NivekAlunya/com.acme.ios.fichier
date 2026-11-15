//
//  TVPlayerContainerUIView.swift
//  FichierTV
//

import UIKit
import AVFoundation

/// `UIView` backed directly by `AVPlayerLayer` so video bounds scale automatically with SwiftUI layout.
public final class TVPlayerContainerUIView: UIView {
    public override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    public var playerLayer: AVPlayerLayer {
        guard let avPlayerLayer = layer as? AVPlayerLayer else {
            assertionFailure("TVPlayerContainerUIView layer is not an AVPlayerLayer")
            return AVPlayerLayer()
        }
        return avPlayerLayer
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
