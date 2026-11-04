//
//  PlayerUIView.swift
//  fichier
//

import UIKit
import AVFoundation

/// Custom UIKit view backed by `AVPlayerLayer` for high-performance hardware video rendering.
///
/// Features:
/// - Overrides `layerClass` to return `AVPlayerLayer.self`, avoiding manual sublayer frame management.
/// - Configures `.resizeAspect` video gravity for letterboxed / pillarboxed presentation without distortion.
/// - Detects two-finger single taps to toggle play/pause via `UITapGestureRecognizer`.
public final class PlayerUIView: UIView, UIGestureRecognizerDelegate {
    /// Overrides backing layer class to provide a native `AVPlayerLayer`.
    public override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }
    
    /// Typed accessor for the backing `AVPlayerLayer`.
    public var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
    
    /// Callback triggered upon recognizing a two-finger single tap.
    public var onTwoFingerTap: (() -> Void)?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    /// Configures black background, aspect scaling, and two-finger tap gesture recognizers.
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
    
    /// Enables simultaneous gesture recognition with system navigation gestures.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}
