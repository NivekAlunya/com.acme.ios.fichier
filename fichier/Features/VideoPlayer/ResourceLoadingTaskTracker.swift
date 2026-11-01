//
//  ResourceLoadingTaskTracker.swift
//  fichier
//

import Foundation
import AVFoundation

actor ResourceLoadingTaskTracker {
    private var activeTasks: [AVAssetResourceLoadingRequest: Task<Void, Never>] = [:]
    private var cancelledRequests: Set<AVAssetResourceLoadingRequest> = []
    private var cancelledOrder: [AVAssetResourceLoadingRequest] = []
    private let maxCancelledCapacity = 64
    private var isStopped = false
    
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
    
    func remove(for request: AVAssetResourceLoadingRequest) {
        activeTasks.removeValue(forKey: request)
        if cancelledRequests.remove(request) != nil {
            cancelledOrder.removeAll(where: { $0 == request })
        }
    }
    
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
    
    func cancelAll() {
        isStopped = true
        let tasks = Array(activeTasks.values)
        activeTasks.removeAll()
        cancelledRequests.removeAll()
        cancelledOrder.removeAll()
        tasks.forEach { $0.cancel() }
    }
}
