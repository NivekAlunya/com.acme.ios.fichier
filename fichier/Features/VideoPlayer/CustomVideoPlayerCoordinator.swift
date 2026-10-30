//
//  CustomVideoPlayerCoordinator.swift
//  fichier
//

import AVKit

@MainActor
public final class CustomVideoPlayerCoordinator: NSObject, AVPlayerViewControllerDelegate, AVPictureInPictureControllerDelegate {
    public var onPiPStatusChanged: ((Bool) -> Void)?
    public private(set) var isPiPActive: Bool = false
    public var pipController: AVPictureInPictureController?
    
    public override init() {
        super.init()
    }
    
    public func togglePiP() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }
    
    // MARK: - AVPlayerViewControllerDelegate
    
    public func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        isPiPActive = true
        onPiPStatusChanged?(true)
    }
    
    public func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        isPiPActive = false
        onPiPStatusChanged?(false)
    }
    
    public func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
    
    // MARK: - AVPictureInPictureControllerDelegate
    
    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
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
