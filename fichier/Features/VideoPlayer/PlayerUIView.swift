//
//  PlayerUIView.swift
//  fichier
//

import UIKit
import AVFoundation

public final class PlayerUIView: UIView {
    public override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }
    
    public var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }
}
