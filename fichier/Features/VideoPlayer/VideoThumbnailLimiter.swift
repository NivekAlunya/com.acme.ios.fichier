//
//  VideoThumbnailLimiter.swift
//  fichier
//

import Foundation

/// Actor-based concurrency limiter for video thumbnail generation and keyframe extraction.
///
/// Restricts simultaneous AVAsset / CoreMedia decompression tasks to prevent
/// saturating memory or exhausting the single SMB socket during video playback.
///
/// ### Concurrency Architecture & Socket Preservation
/// - **Max Concurrency Cap (2)**: Kept strictly conservative (2). All SMB traffic routes
///   through a single TCP socket managed by `SMBClientActor`. Exceeding 2 concurrent streaming
///   probes congests the socket and starves active video playback range requests, causing seek freezes.
/// - **FIFO Continuation Waiters**: Tasks that arrive when all permits are checked out append a
///   `CheckedContinuation` to a FIFO waiting queue.
/// - **Cooperative Cancellation**: Integrates `withTaskCancellationHandler` to automatically
///   resume and remove queued waiters if their parent task is cancelled before acquiring a permit.
public actor VideoThumbnailLimiter {
    private var activeCount = 0
    
    /// Maximum number of concurrent video thumbnail extraction operations.
    private let maxConcurrent: Int
    
    /// Queue of pending continuation waiters awaiting available permits.
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []
    
    /// Initializes the limiter with an optional custom concurrency cap. Defaults to 2.
    ///
    /// - Parameter maxConcurrent: Maximum concurrent operations (clamped to at least 1).
    public init(maxConcurrent: Int = 2) {
        self.maxConcurrent = max(1, maxConcurrent)
    }
    
    /// Executes an asynchronous operation within a regulated concurrency permit.
    ///
    /// - Parameter operation: The work closure to execute once permitted.
    /// - Returns: The result of the operation.
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
    
    /// Requests a permit, returning immediately if below capacity or suspending until released.
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
    
    /// Cancels a pending waiter continuation when its calling task is cancelled.
    private func cancelWaiter(id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        }
    }
    
    /// Releases an active permit and unblocks the next queued FIFO waiter.
    private func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.continuation.resume(returning: true)
        } else {
            activeCount = max(0, activeCount - 1)
        }
    }
}
