//
//  SMBResourceLoaderDelegate.swift
//  fichier
//

import Foundation
import AVFoundation

/// Resource loader delegate enabling progressive on-demand streaming of remote SMB video files into `AVPlayer`.
///
/// Intercepts custom scheme URL requests (`smbstream://`) created by `StorageLocationManager.makeStreamURL(for:)`:
/// 1. **Content Information Requests**: Fills MIME content types (`com.apple.quicktime-movie` for MOV or `public.mpeg-4` for MP4/MKV),
///    byte range access support (`isByteRangeAccessSupported = true`), and total file byte length.
/// 2. **Data Requests**: Streams requested byte ranges in sequential chunks (default 512 KB or 256 KB) via
///    `SMBClientActor.fetchMediaRange(for:offset:length:)`.
/// 3. **Task Tracking & Cancellation**: Delegates async execution to `ResourceLoadingTaskTracker` to ensure
///    out-of-order cancellations and user seeks immediately terminate obsolete network chunk reads.
nonisolated final class SMBResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    /// Background actor handling SMB network connections and byte range reading.
    private let worker: SMBClientActor
    
    /// Target video media item being streamed.
    private let item: MediaItem
    
    /// Byte size per network slice request.
    private let chunkSize: Int
    
    /// Task tracker managing asynchronous task lifecycles and cancellations.
    private let taskTracker = ResourceLoadingTaskTracker()
    
    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - worker: Background SMB client actor.
    ///   - item: Video media item.
    ///   - chunkSize: Chunk buffer size in bytes (defaults to 256 KB).
    init(worker: SMBClientActor, item: MediaItem, chunkSize: Int = 256 * 1024) {
        self.worker = worker
        self.item = item
        self.chunkSize = chunkSize
        super.init()
    }
    
    /// Intercepts AVFoundation resource loading requests to deliver content info and byte range chunks.
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
        let requestID = ObjectIdentifier(loadingRequest)
        
        Task {
            await tracker.runTask(for: requestID, isCancelled: loadingRequest.isCancelled) {
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
    
    /// Handles cancellation notifications when AVFoundation abandons a loading request.
    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let requestID = ObjectIdentifier(loadingRequest)
        Task { [tracker = self.taskTracker] in
            await tracker.cancelTask(for: requestID)
        }
    }
    
    /// Cancels all active in-flight resource loading requests.
    nonisolated func cancelAll() {
        Task { [tracker = self.taskTracker] in
            await tracker.cancelAll()
        }
    }
}
