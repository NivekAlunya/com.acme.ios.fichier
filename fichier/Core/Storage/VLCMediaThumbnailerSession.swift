//
//  VLCMediaThumbnailerSession.swift
//  fichier
//

import Foundation
import UIKit
#if canImport(VLCKit)
import VLCKit
#endif

/// Objective-C delegate bridge executing frame extraction callbacks from `VLCMediaThumbnailer`.
///
/// Dispatches VLCKit C-level thumbnail notifications back to `VLCMediaThumbnailerActor`
/// across thread and actor boundaries.
@MainActor
public final class VLCMediaThumbnailerSession: NSObject {
    private let sessionID: UUID
    private weak var owner: VLCMediaThumbnailerActor?
    
    #if canImport(VLCKit)
    private var thumbnailer: VLCMediaThumbnailer?
    #endif
    private var didComplete = false
    
    /// Initializes a new thumbnailing session.
    ///
    /// - Parameters:
    ///   - sessionID: Unique identifier for tracking this session.
    ///   - owner: Owning actor receiving extraction completion or failure notifications.
    public init(sessionID: UUID, owner: VLCMediaThumbnailerActor) {
        self.sessionID = sessionID
        self.owner = owner
        super.init()
    }
    
    #if canImport(VLCKit)
    /// Starts asynchronous thumbnail generation with VLCKit.
    ///
    /// - Parameters:
    ///   - media: Configured `VLCMedia` instance.
    ///   - maxDimension: Maximum bounding dimension for width and height.
    ///   - snapshotPosition: Relative position within the media timeline (0.0 to 1.0).
    public func start(with media: VLCMedia, maxDimension: CGFloat, snapshotPosition: Float) {
        guard !didComplete else { return }
        let thumb = VLCMediaThumbnailer(media: media, andDelegate: self)
        thumb.thumbnailWidth = maxDimension
        thumb.thumbnailHeight = maxDimension
        thumb.snapshotPosition = snapshotPosition
        self.thumbnailer = thumb
        thumb.fetchThumbnail()
    }
    #endif
    
    /// Cancels the in-flight extraction session and tears down references.
    public func cancel() {
        didComplete = true
        #if canImport(VLCKit)
        self.thumbnailer?.cancel()
        self.thumbnailer = nil
        #endif
        self.owner = nil
    }
    
    private func notifyCompletion(image: UIImage?) {
        guard !didComplete else { return }
        didComplete = true
        
        let id = sessionID
        let currentOwner = owner
        self.owner = nil
        #if canImport(VLCKit)
        self.thumbnailer = nil
        #endif
        
        Task {
            await currentOwner?.handleSessionCompletion(id: id, image: image)
        }
    }
}

#if canImport(VLCKit)
extension VLCMediaThumbnailerSession: VLCMediaThumbnailerDelegate {
    public nonisolated func mediaThumbnailer(
        _ mediaThumbnailer: VLCMediaThumbnailer,
        didFinishThumbnail thumbnail: CGImage
    ) {
        let image = UIImage(cgImage: thumbnail)
        Task { @MainActor [weak self] in
            self?.notifyCompletion(image: image)
        }
    }
    
    public nonisolated func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        Task { @MainActor [weak self] in
            self?.notifyCompletion(image: nil)
        }
    }
}
#endif
