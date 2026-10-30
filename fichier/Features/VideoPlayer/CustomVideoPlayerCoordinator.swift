//
//  CustomVideoPlayerCoordinator.swift
//  fichier
//

import AVKit

@MainActor
public final class CustomVideoPlayerCoordinator: NSObject, AVPictureInPictureControllerDelegate {
    public var onPiPStatusChanged: ((Bool) -> Void)?
    public private(set) var isPiPActive: Bool = false
    public var pipController: AVPictureInPictureController?
    
    public override init() {
        super.init()
    }
    
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
