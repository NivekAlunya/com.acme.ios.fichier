//
//  CustomVideoPlayerCoordinator.swift
//  fichier
//

import AVKit

/// Coordinator managing `AVPictureInPictureControllerDelegate` callbacks and Picture-in-Picture transitions.
///
/// Attaches to an `AVPlayerLayer` to configure inline and background PiP playback:
/// - Sets `canStartPictureInPictureAutomaticallyFromInline = true` so users navigating home seamlessly transition to PiP.
/// - Tracks active PiP presentation status (`isPiPActive`) and broadcasts changes via `onPiPStatusChanged`.
/// - Implements UI restoration (`restoreUserInterfaceForPictureInPictureStopWithCompletionHandler`) when returning from PiP.
@MainActor
public final class CustomVideoPlayerCoordinator: NSObject, AVPictureInPictureControllerDelegate {
    /// Callback delivering Boolean updates when Picture-in-Picture starts or stops.
    public var onPiPStatusChanged: ((Bool) -> Void)?
    
    /// Indicates whether Picture-in-Picture presentation is currently active.
    public private(set) var isPiPActive: Bool = false
    
    /// Underlying system Picture-in-Picture controller.
    public var pipController: AVPictureInPictureController?
    
    public override init() {
        super.init()
    }
    
    /// Initializes and attaches the Picture-in-Picture controller to the specified player layer.
    ///
    /// - Parameter playerLayer: Active `AVPlayerLayer` hosting video rendering.
    public func setupPiP(with playerLayer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        
        if let existing = pipController, existing.isPictureInPictureActive {
            return
        }
        
        let pip = AVPictureInPictureController(playerLayer: playerLayer)
        pip?.canStartPictureInPictureAutomaticallyFromInline = true
        pip?.delegate = self
        self.pipController = pip
    }
    
    /// Toggles Picture-in-Picture presentation on or off.
    public func togglePiP() {
        guard let pip = pipController, pip.isPictureInPicturePossible else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }
    
    // MARK: - AVPictureInPictureControllerDelegate
    
    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
        onPiPStatusChanged?(true)
    }
    
    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
        onPiPStatusChanged?(true)
    }
    
    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
        onPiPStatusChanged?(false)
    }
    
    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
