//
//  VLCMediaThumbnailerSession.swift
//  fichier
//

import Foundation
import UIKit
#if canImport(MobileVLCKit)
import MobileVLCKit
#endif

/// Objective-C delegate bridge executing frame extraction callbacks from `VLCMediaThumbnailer`.
///
/// Dispatches MobileVLCKit C-level thumbnail notifications back to `VLCMediaThumbnailerActor`
/// across thread and actor boundaries.
public final class VLCMediaThumbnailerSession: NSObject, @unchecked Sendable {
    private let sessionID: UUID
    private nonisolated(unsafe) weak var owner: VLCMediaThumbnailerActor?
    
    #if canImport(MobileVLCKit)
    private nonisolated(unsafe) var thumbnailer: VLCMediaThumbnailer?
    #endif
    
    /// Initializes a new thumbnailing session.
    ///
    /// - Parameters:
    ///   - sessionID: Unique identifier for tracking this session.
    ///   - owner: Owning actor receiving extraction completion or failure notifications.
    public nonisolated init(sessionID: UUID, owner: VLCMediaThumbnailerActor) {
        self.sessionID = sessionID
        self.owner = owner
        super.init()
    }
    
    #if canImport(MobileVLCKit)
    /// Starts asynchronous thumbnail generation with MobileVLCKit.
    ///
    /// - Parameters:
    ///   - media: Configured `VLCMedia` instance.
    ///   - maxDimension: Maximum bounding dimension for width and height.
    ///   - snapshotPosition: Relative position within the media timeline (0.0 to 1.0).
    public nonisolated func start(with media: VLCMedia, maxDimension: CGFloat, snapshotPosition: Float) {
        let thumb = VLCMediaThumbnailer(media: media, andDelegate: self)
        thumb.thumbnailWidth = maxDimension
        thumb.thumbnailHeight = maxDimension
        thumb.snapshotPosition = snapshotPosition
        self.thumbnailer = thumb
        thumb.fetchThumbnail()
    }
    #endif
    
    /// Cancels the in-flight extraction session and tears down references.
    public nonisolated func cancel() {
        self.owner = nil
        #if canImport(MobileVLCKit)
        self.thumbnailer = nil
        #endif
    }
    
    private nonisolated func notifyCompletion(image: UIImage?) {
        let owner = self.owner
        let id = self.sessionID
        Task {
            await owner?.handleSessionCompletion(id: id, image: image)
        }
    }
}

#if canImport(MobileVLCKit)
extension VLCMediaThumbnailerSession: VLCMediaThumbnailerDelegate {
    public nonisolated func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
        let image = UIImage(cgImage: thumbnail)
        notifyCompletion(image: image)
    }
    
    public nonisolated func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        notifyCompletion(image: nil)
    }
}
#endif
