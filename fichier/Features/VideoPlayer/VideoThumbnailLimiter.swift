//
//  VideoThumbnailLimiter.swift
//  fichier
//

import Foundation

public actor VideoThumbnailLimiter {
    private var activeCount = 0
    private let maxConcurrent = 2
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    public init() {}
    
    public func withPermit<T: Sendable>(_ operation: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }
    
    private func acquire() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
    
    private func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            activeCount = max(0, activeCount - 1)
        }
    }
}
