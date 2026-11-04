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
    /// Active in-flight background tasks mapped to loading request identifiers.
    private var activeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    
    /// Set of request identifiers whose cancellation arrived before task execution commenced.
    private var cancelledRequests: Set<ObjectIdentifier> = []
    
    /// Ordered list tracking insertion age of early-cancelled requests for capacity bounding.
    private var cancelledOrder: [ObjectIdentifier] = []
    
    /// Bounding limit for early cancellation tracking to prevent memory leaks.
    private let maxCancelledCapacity = 64
    
    /// Indicates whether the tracker has been permanently stopped.
    private var isStopped = false
    
    /// Spawns and tracks an asynchronous task for a given loading request identifier.
    ///
    /// - Parameters:
    ///   - requestID: Unique object identifier for the AVFoundation loading request.
    ///   - isCancelled: Initial cancellation status of the loading request.
    ///   - operation: The asynchronous work closure.
    func runTask(
        for requestID: ObjectIdentifier,
        isCancelled: Bool,
        operation: @Sendable @escaping () async -> Void
    ) {
        if isStopped {
            return
        }
        if cancelledRequests.remove(requestID) != nil {
            cancelledOrder.removeAll(where: { $0 == requestID })
            return
        }
        guard !isCancelled else { return }
        
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            await operation()
            await self?.remove(for: requestID)
        }
        activeTasks[requestID] = task
    }
    
    /// Removes a finished loading request identifier from the active task dictionary.
    func remove(for requestID: ObjectIdentifier) {
        activeTasks.removeValue(forKey: requestID)
        if cancelledRequests.remove(requestID) != nil {
            cancelledOrder.removeAll(where: { $0 == requestID })
        }
    }
    
    /// Cancels the task associated with a loading request identifier or records it in the early cancellation cache.
    func cancelTask(for requestID: ObjectIdentifier) {
        if let task = activeTasks.removeValue(forKey: requestID) {
            task.cancel()
        } else if !isStopped {
            let (inserted, _) = cancelledRequests.insert(requestID)
            if inserted {
                cancelledOrder.append(requestID)
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
