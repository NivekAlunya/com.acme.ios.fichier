//
//  ResourceLoadingTaskTracker.swift
//  fichier
//

import Foundation
import AVFoundation

actor ResourceLoadingTaskTracker {
    private var activeTasks: [AVAssetResourceLoadingRequest: Task<Void, Never>] = [:]
    private var cancelledRequests: Set<AVAssetResourceLoadingRequest> = []
    private var isStopped = false
    
    func runTask(
        for request: AVAssetResourceLoadingRequest,
        operation: @Sendable @escaping () async -> Void
    ) {
        if isStopped || cancelledRequests.remove(request) != nil {
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
        cancelledRequests.remove(request)
    }
    
    func cancelTask(for request: AVAssetResourceLoadingRequest) {
        if let task = activeTasks.removeValue(forKey: request) {
            task.cancel()
        } else if !isStopped {
            cancelledRequests.insert(request)
        }
    }
    
    func cancelAll() {
        isStopped = true
        let tasks = Array(activeTasks.values)
        activeTasks.removeAll()
        cancelledRequests.removeAll()
        tasks.forEach { $0.cancel() }
    }
}
