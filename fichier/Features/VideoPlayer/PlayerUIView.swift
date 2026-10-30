//
//  PlayerUIView.swift
//  fichier
//

import UIKit
import AVFoundation

public final class PlayerUIView: UIView, UIGestureRecognizerDelegate {
    public override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }
    
    public var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
    
    public var onTwoFingerTap: (() -> Void)?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        isUserInteractionEnabled = true
        
        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.cancelsTouchesInView = true
        twoFingerTap.delegate = self
        addGestureRecognizer(twoFingerTap)
    }
    
    @objc private func handleTwoFingerTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .recognized else { return }
        onTwoFingerTap?()
    }
    
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}
