//
//  VideoThumbnailLimiter.swift
//  fichier
//

import Foundation

/// Actor-based concurrency limiter for video thumbnail generation.
/// Restricts simultaneous AVAsset / CoreMedia decompression tasks to prevent
/// saturating memory or exhausting video decoders while maximizing grid loading throughput.
public actor VideoThumbnailLimiter {
    private var activeCount = 0
    /// Maximum number of concurrent video thumbnail extraction operations.
    /// Dynamically adjusted based on processor core count (4 on iPhones, 5 on iPad/Mac).
    private let maxConcurrent: Int
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []
    
    /// Initializes the limiter with an optional custom concurrency cap.
    /// Defaults to 4 concurrent slots on standard mobile hardware and 5 on devices with 8+ cores (iPad Pro, Apple Silicon Macs).
    public init(maxConcurrent: Int? = nil) {
        if let maxConcurrent {
            self.maxConcurrent = max(1, maxConcurrent)
        } else {
            let cores = ProcessInfo.processInfo.activeProcessorCount
            self.maxConcurrent = cores >= 8 ? 5 : 4
        }
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
