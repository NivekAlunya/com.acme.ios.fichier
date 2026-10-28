//
//  ResourceLoadingTaskTracker.swift
//  fichier
//

import Foundation
import AVFoundation

actor ResourceLoadingTaskTracker {
    private var activeTasks: [AVAssetResourceLoadingRequest: Task<Void, Never>] = [:]
    private var cancelledRequests: Set<AVAssetResourceLoadingRequest> = []
    
    func track(task: Task<Void, Never>, for request: AVAssetResourceLoadingRequest) {
        if cancelledRequests.contains(request) {
            cancelledRequests.remove(request)
            task.cancel()
            return
        }
        activeTasks[request] = task
    }
    
    func cancelTask(for request: AVAssetResourceLoadingRequest) {
        if let task = activeTasks.removeValue(forKey: request) {
            task.cancel()
        } else {
            cancelledRequests.insert(request)
        }
    }
    
    func remove(for request: AVAssetResourceLoadingRequest) {
        activeTasks.removeValue(forKey: request)
        cancelledRequests.remove(request)
    }
    
    func cancelAll() {
        let tasks = Array(activeTasks.values)
        activeTasks.removeAll()
        cancelledRequests.removeAll()
        tasks.forEach { $0.cancel() }
    }
}
