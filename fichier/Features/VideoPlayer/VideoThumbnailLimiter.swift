//
//  VideoThumbnailLimiter.swift
//  fichier
//

import Foundation

/// Actor-based concurrency limiter for video thumbnail generation.
/// Restricts simultaneous AVAsset / CoreMedia decompression tasks to prevent
/// saturating memory or exhausting the single SMB socket during video playback.
public actor VideoThumbnailLimiter {
    private var activeCount = 0
    /// Maximum number of concurrent video thumbnail extraction operations.
    /// CRITICAL: Kept strictly conservative (2). Do NOT scale to 4 or 5 based on CPU core count.
    /// All SMB traffic routes through a single TCP socket managed by SMBClientActor; exceeding 2 concurrent
    /// streaming probes congests the socket and starves active video playback range requests, causing seek freezes.
    private let maxConcurrent: Int
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []
    
    /// Initializes the limiter with an optional custom concurrency cap. Defaults to 2.
    public init(maxConcurrent: Int = 2) {
        self.maxConcurrent = max(1, maxConcurrent)
    }
    
    public func withPermit<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        let waiterID = UUID()
        let acquired = await withTaskCancellationHandler {
            await acquire(id: waiterID)
        } onCancel: {
            Task {
                await self.cancelWaiter(id: waiterID)
            }
        }
        defer {
            if acquired {
                release()
            }
        }
        return try await operation()
    }
    
    private func acquire(id: UUID) async -> Bool {
        if Task.isCancelled {
            return false
        }
        if activeCount < maxConcurrent {
            activeCount += 1
            return true
        }
        return await withCheckedContinuation { continuation in
            if Task.isCancelled {
                continuation.resume(returning: false)
                return
            }
            waiters.append((id: id, continuation: continuation))
        }
    }
    
    private func cancelWaiter(id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        }
    }
    
    private func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.continuation.resume(returning: true)
        } else {
            activeCount = max(0, activeCount - 1)
        }
    }
}
