//
//  SMBResourceLoaderDelegate.swift
//  fichier
//

import Foundation
import AVFoundation

nonisolated final class SMBResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    private let worker: SMBClientActor
    private let item: MediaItem
    private let chunkSize: Int
    private let taskTracker = ResourceLoadingTaskTracker()
    
    init(worker: SMBClientActor, item: MediaItem, chunkSize: Int = 256 * 1024) {
        self.worker = worker
        self.item = item
        self.chunkSize = chunkSize
        super.init()
    }
    
    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        // 1. Content Information Request
        if let info = loadingRequest.contentInformationRequest {
            let ext = (item.name as NSString).pathExtension.lowercased()
            if ext == "mov" {
                info.contentType = "com.apple.quicktime-movie"
            } else {
                info.contentType = "public.mpeg-4"
            }
            info.contentLength = max(1, item.size)
            info.isByteRangeAccessSupported = true
        }
        
        // 2. Data Request (Stream Byte Range on Demand in Fast 1MB Chunks)
        guard let dataRequest = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return true
        }
        
        let startOffset = dataRequest.currentOffset
        let requestedLength = dataRequest.requestedLength
        let total = item.size
        
        let safeLength: Int
        if total > 0 {
            let remaining = max(0, total - startOffset)
            safeLength = min(requestedLength, Int(remaining))
        } else {
            safeLength = requestedLength
        }
        
        guard safeLength > 0 else {
            loadingRequest.finishLoading()
            return true
        }
        
        let targetEnd = startOffset + Int64(safeLength)
        let tracker = self.taskTracker
        let worker = self.worker
        let item = self.item
        let chunkSize = self.chunkSize
        
        Task {
            await tracker.runTask(for: loadingRequest) {
                do {
                    var currentOffset = startOffset
                    
                    while currentOffset < targetEnd {
                        if Task.isCancelled || loadingRequest.isCancelled {
                            return
                        }
                        
                        let bytesToRead = min(chunkSize, Int(targetEnd - currentOffset))
                        // Fetch the requested chunk via SMBClientActor.
                        // The worker automatically recovers from transient socket drops and renegotiates
                        // the SMB share connection transparently before failing this loading request.
                        let chunk = try await worker.fetchMediaRange(
                            for: item,
                            offset: currentOffset,
                            length: bytesToRead
                        )
                        
                        if Task.isCancelled || loadingRequest.isCancelled {
                            return
                        }
                        if chunk.isEmpty { break }
                        
                        dataRequest.respond(with: chunk)
                        currentOffset += Int64(chunk.count)
                    }
                    
                    if !Task.isCancelled && !loadingRequest.isCancelled && !loadingRequest.isFinished {
                        loadingRequest.finishLoading()
                    }
                } catch {
                    if !Task.isCancelled && !loadingRequest.isCancelled && !loadingRequest.isFinished {
                        loadingRequest.finishLoading(with: error)
                    }
                }
            }
        }
        
        return true
    }
    
    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        Task { [tracker = self.taskTracker] in
            await tracker.cancelTask(for: loadingRequest)
        }
    }
    
    nonisolated func cancelAll() {
        Task { [tracker = self.taskTracker] in
            await tracker.cancelAll()
        }
    }
}
