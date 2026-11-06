//
//  PDFThumbnailLimiter.swift
//  fichier
//

import Foundation

/// Actor-based concurrency limiter for remote PDF document thumbnail generation and staging.
///
/// Restricts simultaneous PDFKit parsing and SMB download tasks to prevent
/// saturating memory or exhausting the single SMB socket during grid browsing.
///
/// ### Concurrency Architecture & Socket Preservation
/// - **Max Concurrency Cap (1)**: Restricts remote PDF downloads to 1 concurrent operation.
///   All SMB network traffic routes through a single TCP socket managed by `SMBClientActor`.
///   Concurrent multi-megabyte document transfers congest the socket, starve folder navigation,
///   and induce network timeouts.
/// - **FIFO Continuation Waiters**: Tasks that arrive when a download permit is checked out append a
///   `CheckedContinuation` to a FIFO waiting queue.
/// - **Cooperative Cancellation**: Integrates `withTaskCancellationHandler` to automatically
///   resume and remove queued waiters if their parent task is cancelled before acquiring a permit.
public actor PDFThumbnailLimiter {
    private var activeCount = 0
    
    /// Maximum number of concurrent PDF document download operations.
    private let maxConcurrent: Int
    
    /// Queue of pending continuation waiters awaiting available permits.
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []
    
    /// Initializes the limiter with an optional custom concurrency cap. Defaults to 1.
    ///
    /// - Parameter maxConcurrent: Maximum concurrent operations (clamped to at least 1).
    public init(maxConcurrent: Int = 1) {
        self.maxConcurrent = max(1, maxConcurrent)
    }
    
    /// Executes an asynchronous operation within a regulated concurrency permit.
    ///
    /// - Parameter operation: The work closure to execute once permitted.
    /// - Returns: The result of the operation.
    /// - Throws: `CancellationError` if the task is cancelled before acquiring or during execution.
    public func withPermit<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        let waiterID = UUID()
        let acquired = await withTaskCancellationHandler {
            await acquire(id: waiterID)
        } onCancel: {
            Task {
                await self.cancelWaiter(id: waiterID)
            }
        }
        guard acquired, !Task.isCancelled else {
            if acquired {
                release()
            }
            throw CancellationError()
        }
        defer {
            release()
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
