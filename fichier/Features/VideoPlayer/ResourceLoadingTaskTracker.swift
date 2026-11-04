//
//  ResourceLoadingTaskTracker.swift
//  fichier
//

import Foundation
import AVFoundation

/// Background actor coordinating active asynchronous tasks spawned by `SMBResourceLoaderDelegate`.
///
/// ### Out-Of-Order Cancellation Handling
/// AVFoundation's resource loading pipeline can occasionally deliver `didCancel` callbacks
/// *before* the asynchronous task for `shouldWaitForLoadingOfRequestedResource` has finished registering.
/// To handle race conditions and prevent orphan tasks:
/// - Maintains an `activeTasks` dictionary keyed by `AVAssetResourceLoadingRequest`.
/// - Records early cancellation notices in a bounded LRU `cancelledRequests` set (capacity 64).
/// - If a request arrives that is already in `cancelledRequests`, it is immediately discarded without running.
actor ResourceLoadingTaskTracker {
    /// Active in-flight background tasks mapped to loading requests.
    private var activeTasks: [AVAssetResourceLoadingRequest: Task<Void, Never>] = [:]
    
    /// Set of requests whose cancellation arrived before task execution commenced.
    private var cancelledRequests: Set<AVAssetResourceLoadingRequest> = []
    
    /// Ordered list tracking insertion age of early-cancelled requests for capacity bounding.
    private var cancelledOrder: [AVAssetResourceLoadingRequest] = []
    
    /// Bounding limit for early cancellation tracking to prevent memory leaks.
    private let maxCancelledCapacity = 64
    
    /// Indicates whether the tracker has been permanently stopped.
    private var isStopped = false
    
    /// Spawns and tracks an asynchronous task for a given loading request.
    ///
    /// - Parameters:
    ///   - request: The AVFoundation resource loading request.
    ///   - operation: The asynchronous work closure.
    func runTask(
        for request: AVAssetResourceLoadingRequest,
        operation: @Sendable @escaping () async -> Void
    ) {
        if isStopped {
            return
        }
        if cancelledRequests.remove(request) != nil {
            cancelledOrder.removeAll(where: { $0 == request })
            return
        }
        guard !request.isCancelled else { return }
        
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            await operation()
            await self?.remove(for: request)
        }
        activeTasks[request] = task
    }
    
    /// Removes a finished loading request from the active task dictionary.
    func remove(for request: AVAssetResourceLoadingRequest) {
        activeTasks.removeValue(forKey: request)
        if cancelledRequests.remove(request) != nil {
            cancelledOrder.removeAll(where: { $0 == request })
        }
    }
    
    /// Cancels the task associated with a loading request or records it in the early cancellation cache.
    func cancelTask(for request: AVAssetResourceLoadingRequest) {
        if let task = activeTasks.removeValue(forKey: request) {
            task.cancel()
        } else if !isStopped {
            let (inserted, _) = cancelledRequests.insert(request)
            if inserted {
                cancelledOrder.append(request)
                if cancelledOrder.count > maxCancelledCapacity {
                    let oldest = cancelledOrder.removeFirst()
                    cancelledRequests.remove(oldest)
                }
            }
        }
    }
    
    /// Permanently halts tracking and cancels all active in-flight resource loading tasks.
    func cancelAll() {
        isStopped = true
        let tasks = Array(activeTasks.values)
        activeTasks.removeAll()
        cancelledRequests.removeAll()
        cancelledOrder.removeAll()
        tasks.forEach { $0.cancel() }
    }
}
