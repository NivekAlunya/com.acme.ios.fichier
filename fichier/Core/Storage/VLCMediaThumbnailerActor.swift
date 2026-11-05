//
//  VLCMediaThumbnailerActor.swift
//  fichier
//

import Foundation
import UIKit
#if canImport(MobileVLCKit)
import MobileVLCKit
#endif

/// Thread-safe actor coordinating background video thumbnail extraction via MobileVLCKit.
///
/// Serializes LibVLC extraction sessions to ensure low memory pressure and stable process state,
/// and enforces watchdog timeouts to prevent deadlocks on corrupt media streams.
public actor VLCMediaThumbnailerActor {
    /// Shared singleton instance for extended video thumbnailing.
    public static let shared = VLCMediaThumbnailerActor()
    
    private var pendingRequests: [UUID: CheckedContinuation<UIImage?, Never>] = [:]
    private var activeSessions: [UUID: VLCMediaThumbnailerSession] = [:]
    
    private init() {}
    
    /// Generates a thumbnail for an extended video file from a local or stream URL.
    ///
    /// - Parameters:
    ///   - url: Target file or HTTP stream URL.
    ///   - maxDimension: Maximum pixel bounding dimension for the rendered thumbnail.
    ///   - snapshotPosition: Relative position within the media timeline (0.0 to 1.0).
    ///   - timeoutSeconds: Watchdog timeout in seconds (defaults to 4.0).
    /// - Returns: A rendered `UIImage`, or `nil` on failure or timeout.
    public func generateThumbnail(
        from url: URL,
        maxDimension: CGFloat = MediaCacheManager.standardThumbnailDimension,
        snapshotPosition: Float = 0.05,
        timeoutSeconds: Double = 4.0
    ) async -> UIImage? {
        #if canImport(MobileVLCKit)
        let sessionID = UUID()
        let media = VLCMedia(url: url)
        let session = VLCMediaThumbnailerSession(sessionID: sessionID, owner: self)
        self.activeSessions[sessionID] = session
        
        return await withCheckedContinuation { continuation in
            self.pendingRequests[sessionID] = continuation
            session.start(with: media, maxDimension: maxDimension, snapshotPosition: snapshotPosition)
            
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                await self?.handleWatchdogTimeout(for: sessionID)
            }
        }
        #else
        return nil
        #endif
    }
    
    /// Internal callback invoked by `VLCMediaThumbnailerSession` upon successful extraction or failure.
    public func handleSessionCompletion(id: UUID, image: UIImage?) {
        guard let continuation = pendingRequests.removeValue(forKey: id) else { return }
        if let session = activeSessions.removeValue(forKey: id) {
            session.cancel()
        }
        continuation.resume(returning: image)
    }
    
    private func handleWatchdogTimeout(for id: UUID) {
        guard let continuation = pendingRequests.removeValue(forKey: id) else { return }
        if let session = activeSessions.removeValue(forKey: id) {
            session.cancel()
        }
        continuation.resume(returning: nil)
    }
}
