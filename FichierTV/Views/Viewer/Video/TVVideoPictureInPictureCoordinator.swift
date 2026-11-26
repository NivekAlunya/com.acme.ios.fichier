//
//  TVVideoPictureInPictureCoordinator.swift
//  FichierTV
//
//  Coordinates native AVPictureInPictureController lifecycle on tvOS.
//

import AVKit

/// Coordinator managing `AVPictureInPictureControllerDelegate` callbacks and Picture-in-Picture transitions on tvOS.
@MainActor
public final class TVVideoPictureInPictureCoordinator: NSObject, @MainActor AVPictureInPictureControllerDelegate {
    /// Callback delivering Boolean updates when Picture-in-Picture starts or stops.
    public var onPiPStatusChanged: ((Bool) -> Void)?

    /// Indicates whether Picture-in-Picture presentation is currently active.
    public private(set) var isPiPActive: Bool = false

    /// Underlying system Picture-in-Picture controller.
    public private(set) var pipController: AVPictureInPictureController?

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

    /// Tears down the Picture-in-Picture controller reference when playback ends.
    public func reset() {
        if let pip = pipController, pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        }
        pipController = nil
        isPiPActive = false
    }

    // MARK: - AVPictureInPictureControllerDelegate

    public func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isPiPActive = true
        onPiPStatusChanged?(true)
    }

    public func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isPiPActive = true
        onPiPStatusChanged?(true)
    }

    public func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
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
