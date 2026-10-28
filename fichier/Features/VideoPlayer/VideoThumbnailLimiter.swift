//
//  VideoThumbnailLimiter.swift
//  fichier
//

import Foundation

final class VideoThumbnailLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var activeCount = 0
    private let maxConcurrent = 2
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    func acquire() async {
        let shouldWait = lock.withLock { () -> Bool in
            if activeCount < maxConcurrent {
                activeCount += 1
                return false
            } else {
                return true
            }
        }
        if shouldWait {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    waiters.append(continuation)
                }
            }
        }
    }
    
    func release() {
        lock.withLock {
            if !waiters.isEmpty {
                let next = waiters.removeFirst()
                next.resume()
            } else {
                activeCount = max(0, activeCount - 1)
            }
        }
    }
}
