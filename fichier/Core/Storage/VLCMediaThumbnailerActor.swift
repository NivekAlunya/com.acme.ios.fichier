//
//  VLCMediaThumbnailerActor.swift
//  fichier
//

import Foundation
import UIKit
import CoreMedia
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
    private var inFlightCount: Int = 0
    private let maxConcurrentSessions: Int = 1
    private var waitQueue: [CheckedContinuation<Void, Never>] = []
    
    private init() {}
    
    /// Acquires a concurrency permit, suspending if an extraction session is already active.
    private func acquirePermit() async {
        if inFlightCount < maxConcurrentSessions {
            inFlightCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waitQueue.append(continuation)
        }
    }
    
    /// Releases the active permit and resumes the next queued extraction request if available.
    private func releasePermit() {
        if !waitQueue.isEmpty {
            let next = waitQueue.removeFirst()
            next.resume()
        } else {
            inFlightCount = max(0, inFlightCount - 1)
        }
    }
    
    /// Generates a thumbnail for an extended video file from a local or stream URL at a preferred timestamp.
    ///
    /// - Parameters:
    ///   - url: Target file or HTTP stream URL.
    ///   - maxDimension: Maximum pixel bounding dimension for the rendered thumbnail.
    ///   - preferredTime: Target timestamp in CMTime.
    ///   - timeoutSeconds: Watchdog timeout in seconds (defaults to 4.0).
    /// - Returns: A rendered `UIImage`, or `nil` on failure or timeout.
    public func generateThumbnail(
        from url: URL,
        maxDimension: CGFloat = MediaCacheManager.standardThumbnailDimension,
        preferredTime: CMTime = MediaCacheManager.defaultVideoThumbnailTime,
        timeoutSeconds: Double = 4.0
    ) async -> UIImage? {
        #if canImport(MobileVLCKit)
        guard !Task.isCancelled else { return nil }
        await acquirePermit()
        defer { releasePermit() }
        guard !Task.isCancelled else { return nil }
        
        let sessionID = UUID()
        let media = VLCMedia(url: url)
        
        let position: Float
        if preferredTime <= .zero {
            position = 0.0
        } else {
            let preferredSeconds = preferredTime.seconds
            if preferredSeconds.isFinite && !preferredSeconds.isNaN && preferredSeconds > 0 {
                let waitLimit = Date().addingTimeInterval(0.35)
                let lengthTime = media.lengthWait(until: waitLimit)
                let totalSeconds = Double(lengthTime.intValue) / 1000.0
                if totalSeconds > 0 {
                    let fraction = Float(preferredSeconds / totalSeconds)
                    position = min(0.95, max(0.0, fraction))
                } else {
                    position = Float(min(0.95, max(0.02, preferredSeconds / 300.0)))
                }
            } else {
                position = 0.05
            }
        }
        
        let session = VLCMediaThumbnailerSession(sessionID: sessionID, owner: self)
        self.activeSessions[sessionID] = session
        
        return await withCheckedContinuation { continuation in
            self.pendingRequests[sessionID] = continuation
            session.start(with: media, maxDimension: maxDimension, snapshotPosition: position)
            
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                await self?.handleWatchdogTimeout(for: sessionID)
            }
        }
        #else
        return nil
        #endif
    }
    
    /// Generates a thumbnail for an extended video file using a direct relative snapshot position (0.0 to 1.0).
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
        snapshotPosition: Float,
        timeoutSeconds: Double = 4.0
    ) async -> UIImage? {
        #if canImport(MobileVLCKit)
        guard !Task.isCancelled else { return nil }
        await acquirePermit()
        defer { releasePermit() }
        guard !Task.isCancelled else { return nil }
        
        let sessionID = UUID()
        let media = VLCMedia(url: url)
        let session = VLCMediaThumbnailerSession(sessionID: sessionID, owner: self)
        self.activeSessions[sessionID] = session
        
        return await withCheckedContinuation { continuation in
            self.pendingRequests[sessionID] = continuation
            let clamped = min(1.0, max(0.0, snapshotPosition))
            session.start(with: media, maxDimension: maxDimension, snapshotPosition: clamped)
            
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
