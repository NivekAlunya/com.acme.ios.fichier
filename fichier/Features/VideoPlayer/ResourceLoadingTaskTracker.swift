//
//  ResourceLoadingTaskTracker.swift
//  fichier
//

import Foundation
import AVFoundation

actor ResourceLoadingTaskTracker {
    private var activeTasks: [AVAssetResourceLoadingRequest: Task<Void, Never>] = [:]
    
    func runTask(
        for request: AVAssetResourceLoadingRequest,
        operation: @Sendable @escaping () async -> Void
    ) {
        guard !request.isCancelled else { return }
        
        let task = Task { [weak self] in
            await operation()
            await self?.remove(for: request)
        }
        activeTasks[request] = task
    }
    
    func remove(for request: AVAssetResourceLoadingRequest) {
        activeTasks.removeValue(forKey: request)
    }
    
    func cancelTask(for request: AVAssetResourceLoadingRequest) {
        activeTasks.removeValue(forKey: request)?.cancel()
    }
    
    func cancelAll() {
        let tasks = Array(activeTasks.values)
        activeTasks.removeAll()
        tasks.forEach { $0.cancel() }
    }
}
