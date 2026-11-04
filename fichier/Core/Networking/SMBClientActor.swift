//
//  SMBClientActor.swift
//  fichier
//

import Foundation
import UIKit
import CoreGraphics
import ImageIO
import AMSMB2
import AVFoundation
import OSLog

/// A serialized network actor responsible for coordinating all low-level SMB2/3 operations.
///
/// ### Architecture & Concurrency Overview
/// - **Socket Thread-Safety**: The underlying C-library `libsmb2` is not thread-safe over a single TCP socket connection.
///   Isolating all client commands within `actor SMBClientActor` strictly serializes I/O requests, preventing protocol framing collisions.
/// - **Lockless Synchronous Thumbnail Lookups**: Exposes `thumbnailCache` as `nonisolated` via `ThreadSafeMemoryCache`
///   so SwiftUI rendering passes can query cached images synchronously without awaiting the actor's busy I/O mailbox.
/// - **Atomic Persistence**: Large video and document downloads stream to ephemeral `.part` files on disk and are promoted
///   atomically to their destination paths once integrity and cancellation checks pass.
/// - **Zero-Full-Download EXIF Streaming**: Extracts photo metadata by issuing a 64 KB range request over SMB, bypassing
///   multi-megabyte full-file downloads.
actor SMBClientActor {
    
    // MARK: - State Properties
    
    /// The active `AMSMB2` manager instance managing the underlying TCP socket and protocol state.
    private var client: SMB2Manager?
    
    /// The unique identifier of the currently connected saved server configuration.
    private var currentConnectionID: String = ""
    
    /// The name of the currently mounted SMB share (e.g. "Public", "Media").
    private var currentShareName: String?
    
    /// Active directory identifier used to cancel or drop out-of-date thumbnail requests when the user rapidly switches folders.
    private var activeFolderID: String?
    
    /// High-performance thread-safe in-memory cache for downsampled thumbnails.
    /// Marked `nonisolated` to allow instant, non-blocking synchronous cache hits on the main thread.
    nonisolated private let thumbnailCache = ThreadSafeMemoryCache<NSString, UIImage>()
    
    /// Bounded in-memory cache for full-resolution pictures, sized dynamically according to physical system RAM.
    private let fullImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 5
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        // Dynamically scale in-memory cache limit on low-RAM devices (~187 MB on 3 GB hardware) while capping at 250 MB on 4+ GB devices
        cache.totalCostLimit = Int(min(Int64(250 * 1024 * 1024), Int64(physicalMemory / 16)))
        return cache
    }()
    
    /// In-memory cache storing parsed EXIF metadata boxes indexed by `MediaItem.id`.
    private let metadataCache = NSCache<NSString, PictureEXIFBox>()
    
    // MARK: - Active Directory Scope
    
    /// Updates the active folder identifier to facilitate cooperative cancellation of background thumbnail queues.
    ///
    /// - Parameter id: The unique path or ID string of the newly navigated directory.
    func setActiveFolder(id: String?) {
        self.activeFolderID = id
    }
    
    // MARK: - Nonisolated In-Memory Thumbnail Cache Access
    
    /// Synchronously retrieves a cached thumbnail from memory without queuing on the actor mailbox.
    ///
    /// - Parameter key: The cache key string.
    /// - Returns: The cached `UIImage`, or `nil` if not present.
    nonisolated func getCachedThumbnail(forKey key: NSString) -> UIImage? {
        thumbnailCache.object(forKey: key)
    }
    
    /// Stores a rendered thumbnail directly into the nonisolated in-memory cache.
    ///
    /// - Parameters:
    ///   - image: The downsampled thumbnail image.
    ///   - key: The unique cache key string.
    nonisolated func cacheThumbnail(_ image: UIImage, forKey key: NSString) {
        thumbnailCache.setObject(image, forKey: key)
    }
    
    // MARK: - Share Enumeration & Connection Management
    
    /// Maps raw share names and comments into canonical `MediaItem` folder entities.
    ///
    /// - Parameters:
    ///   - shares: Raw tuples containing share names and commentary returned by the SMB IPC$ pipe.
    ///   - connectionID: The connection identifier assigned to the host.
    /// - Returns: A sorted list of root directory `MediaItem` instances.
    private func makeShareItems(from shares: [(name: String, comment: String)], connectionID: String) -> [MediaItem] {
        shares
            .map { share in
                MediaItem(
                    locationID: connectionID,
                    name: share.name,
                    rootName: share.name,
                    path: "/",
                    isDirectory: true,
                    size: 0,
                    children: nil
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    /// Connects to an SMB host, validates user credentials, and automatically enumerates all non-hidden shared volumes.
    ///
    /// - Parameters:
    ///   - url: The network URL identifying the host (`smb://host:port`).
    ///   - credential: The username and password credential pair.
    ///   - connectionID: The stable identifier for the connection profile.
    /// - Returns: A list of discovered root shares.
    /// - Throws: `URLError(.badURL)` if connection initialization fails.
    func connectAndListShares(url: URL, credential: URLCredential, connectionID: String = "") async throws -> [MediaItem] {
        guard let manager = SMB2Manager(url: url, credential: credential) else {
            throw URLError(.badURL)
        }
        
        // Fetch all non-hidden shares from the remote host via IPC$
        let shares = try await manager.listShares(enumerateHidden: false)
        try? await self.client?.disconnectShare()
        self.client = manager
        self.currentConnectionID = connectionID
        self.currentShareName = nil
        
        return makeShareItems(from: shares, connectionID: connectionID)
    }
    
    /// Refreshes the list of available shares on the currently active connection.
    ///
    /// - Returns: An updated list of root shares.
    /// - Throws: `URLError(.notConnectedToInternet)` if no client session is currently active.
    func refreshShares() async throws -> [MediaItem] {
        guard let client else {
            throw URLError(.notConnectedToInternet)
        }
        let shares = try await client.listShares(enumerateHidden: false)
        self.currentShareName = nil
        return makeShareItems(from: shares, connectionID: self.currentConnectionID)
    }
    
    /// Mounts and connects to a specific named share if not already active, optionally forcing a socket reconnection.
    ///
    /// - Parameters:
    ///   - shareName: The volume name to connect to.
    ///   - forceReconnect: When `true`, explicitly tears down existing tree connections before reconnecting.
    /// - Returns: The verified `SMB2Manager` instance ready for file I/O.
    /// - Throws: `URLError(.notConnectedToInternet)` if disconnected.
    private func ensureConnected(to shareName: String, forceReconnect: Bool = false) async throws -> SMB2Manager {
        guard let client else {
            throw URLError(.notConnectedToInternet)
        }
        if forceReconnect || currentShareName != shareName {
            if forceReconnect {
                try? await client.disconnectShare()
                currentShareName = nil
            }
            try await client.connectShare(name: shareName)
            currentShareName = shareName
        }
        return client
    }
    
    /// Disconnects from the current SMB share and purges all in-memory image and metadata caches.
    func disconnect() async {
        try? await client?.disconnectShare()
        client = nil
        currentConnectionID = ""
        currentShareName = nil
        thumbnailCache.removeAllObjects()
        fullImageCache.removeAllObjects()
        metadataCache.removeAllObjects()
    }
    
    // MARK: - Directory Enumeration
    
    /// Scans a directory within a specific share and segregates entries into subfolders and supported media files.
    ///
    /// ### Complex Code Breakdown:
    /// - **Automatic Socket Recovery**: Executes inside an attempt loop (`maxAttempts = 2`). If a network glitch drops
    ///   the TCP session, attempt 2 triggers `ensureConnected(..., forceReconnect: true)` with backoff sleep.
    /// - **Cancellation Checking**: Evaluates `Task.checkCancellation()` before and after every asynchronous network call.
    /// - **Hidden File Filtering**: Automatically ignores UNIX hidden entries (starting with `.`) and dot-underscore AppleDouble files.
    ///
    /// - Parameters:
    ///   - shareName: The name of the share volume.
    ///   - path: The directory path relative to the share root.
    /// - Returns: A tuple containing sorted subfolders and media items.
    /// - Throws: `CancellationError` if cancelled, or network error upon exhausted attempts.
    func scanFolder(shareName: String, at path: String) async throws -> (folders: [MediaItem], pictures: [MediaItem]) {
        let maxAttempts = 2
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let client = try await ensureConnected(to: shareName, forceReconnect: attempt > 1)
                try Task.checkCancellation()
                
                let normalizedPath = path == "/" ? "" : path
                let entries = try await client.contentsOfDirectory(atPath: normalizedPath)
                try Task.checkCancellation()
                
                var folders: [MediaItem] = []
                var pictures: [MediaItem] = []
                let connID = self.currentConnectionID
                
                for entry in entries {
                    if Task.isCancelled { throw CancellationError() }
                    guard let name = entry[.nameKey] as? String,
                          !name.hasPrefix(".") else { continue }
                    
                    let resourceType = entry[.fileResourceTypeKey] as? URLFileResourceType
                    let entryPath = (entry[.pathKey] as? String) ?? (normalizedPath.isEmpty ? name : (normalizedPath as NSString).appendingPathComponent(name))
                    let modDate = entry[.contentModificationDateKey] as? Date
                    
                    if resourceType == .directory {
                        folders.append(MediaItem(
                            locationID: connID,
                            name: name,
                            rootName: shareName,
                            path: entryPath,
                            isDirectory: true,
                            size: 0,
                            modifiedDate: modDate,
                            children: nil
                        ))
                    } else if resourceType == .regular {
                        let ext = (name as NSString).pathExtension.lowercased()
                        if SupportedMediaTypes.isSupported(extension: ext) {
                            let size = Self.extractFileSize(from: entry)
                            pictures.append(MediaItem(
                                locationID: connID,
                                name: name,
                                rootName: shareName,
                                path: entryPath,
                                isDirectory: false,
                                size: size,
                                modifiedDate: modDate
                            ))
                        }
                    }
                }
                
                try Task.checkCancellation()
                folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                pictures.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                
                return (folders, pictures)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
                if attempt < maxAttempts {
                    // Brief pause to allow the network interface or server socket to stabilize
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        }
        
        throw lastError ?? URLError(.cannotConnectToHost)
    }
    
    // MARK: - Thumbnail Retrieval & Downsampling
    
    /// Fetches and downsamples a media thumbnail using a 2-tier caching hierarchy (RAM + Disk).
    ///
    /// ### Complex Code Breakdown:
    /// 1. **RAM Cache (Tier 1)**: Checked first via synchronous `ThreadSafeMemoryCache`.
    /// 2. **Persistent Disk Cache (Tier 2)**: Checks for pre-rendered JPEG thumbnails stored in Caches directory, bypassing SMB I/O entirely.
    /// 3. **Scope Guard**: Validates `expectedFolderID == activeFolderID` to discard requests if the user has navigated away.
    /// 4. **PDF Staging**: Remote PDFs stream to a temporary local file so `CGPDFDocument` can render the cover without buffering entire books in RAM.
    /// 5. **Off-Actor Detached Downsampling**: CPU-intensive image resizing executes within `Task.detached(priority: .userInitiated)`
    ///    to immediately free up the actor's mailbox for incoming network packets.
    ///
    /// - Parameters:
    ///   - item: The target `MediaItem`.
    ///   - expectedFolderID: The folder ID at the time the request was dispatched.
    ///   - maxDimension: Maximum pixel dimension for the rendered thumbnail.
    /// - Returns: A downsampled `UIImage`, or `nil` on failure or cancellation.
    func fetchThumbnail(for item: MediaItem, expectedFolderID: String? = nil, maxDimension: CGFloat = MediaCacheManager.standardThumbnailDimension) async -> UIImage? {
        if Task.isCancelled || item.isVideo { return nil }
        if let expected = expectedFolderID, let active = activeFolderID, expected != active {
            return nil
        }
        
        // 1. In-Memory RAM Cache check (Tier 1) - unified across all view modes
        let memoryCacheKey = "\(item.id)_thumb" as NSString
        let legacyMemoryKey = "\(item.id)_thumb_\(Int(maxDimension))" as NSString
        if let cached = thumbnailCache.object(forKey: memoryCacheKey) ?? thumbnailCache.object(forKey: legacyMemoryKey) {
            return cached
        }
        
        // 2. Persistent On-Disk Cache check (Tier 2 - Bypasses Wi-Fi / SMB completely!)
        let (diskKey, fallbackKey, legacyKey) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: maxDimension,
            connectionID: item.connectionID
        )
        if let diskCached = MediaCacheManager.shared.getThumbnail(for: diskKey, fallbackKey: fallbackKey, legacyKey: legacyKey) {
            thumbnailCache.setObject(diskCached, forKey: memoryCacheKey)
            return diskCached
        }
        
        // 3. For PDF documents already cached on disk in SMBDocuments, generate thumbnail directly from disk file
        if item.isPDF && MediaCacheManager.shared.hasCachedDocument(for: item) {
            let docURL = MediaCacheManager.shared.localDocumentURL(for: item)
            if let thumb = MediaCacheManager.shared.generatePDFThumbnail(from: docURL, maxDimension: maxDimension) {
                thumbnailCache.setObject(thumb, forKey: memoryCacheKey)
                MediaCacheManager.shared.saveThumbnail(thumb, for: diskKey)
                return thumb
            }
        }
        
        if Task.isCancelled { return nil }
        if let expected = expectedFolderID, let active = activeFolderID, expected != active {
            return nil
        }
        
        do {
            let client = try await ensureConnected(to: item.shareName)
            if Task.isCancelled { return nil }
            if let expected = expectedFolderID, let active = activeFolderID, expected != active {
                return nil
            }
            
            // Remote PDF: Fast-path prefix thumbnailing with bounded fallback
            if item.isPDF {
                if let prefixThumb = await fetchPDFPrefixThumbnail(for: item, maxDimension: maxDimension) {
                    return prefixThumb
                }
                
                // Fallback for non-linearized documents: fetch full document if within safe bounded size (< 12 MB)
                // to prevent socket starvation during gallery browsing
                let maxDirectDownloadBytes: Int64 = 12 * 1024 * 1024
                if item.size > 0 && item.size <= maxDirectDownloadBytes {
                    do {
                        let localURL = try await fetchDocumentURL(for: item)
                        if let thumb = MediaCacheManager.shared.generatePDFThumbnail(from: localURL, maxDimension: maxDimension) {
                            thumbnailCache.setObject(thumb, forKey: memoryCacheKey)
                            MediaCacheManager.shared.saveThumbnail(thumb, for: diskKey)
                            return thumb
                        }
                    } catch {
                        if !Task.isCancelled {
                            AppLog.smb.warning("Fallback PDF thumbnailing failed at \(item.shareName, privacy: .private)/\(item.path, privacy: .private): \(error.localizedDescription)")
                        }
                    }
                }
                return nil
            }
            
            // Photo Thumbnail Handling
            let data = try await client.contents(atPath: item.path) { _, _ in
                !Task.isCancelled
            }
            if Task.isCancelled { return nil }
            if let expected = expectedFolderID, let active = activeFolderID, expected != active {
                return nil
            }
            
            // Extract and cache metadata immediately while image bytes are in memory!
            if metadataCache.object(forKey: item.id as NSString) == nil {
                let meta = ImageMetadataExtractor.extract(from: data, fileName: item.name, fileSize: item.formattedSize)
                metadataCache.setObject(PictureEXIFBox(meta), forKey: item.id as NSString)
            }
            
            // Offload CPU-bound image downsampling and disk caching off the actor lock
            // Standardize downsampling to master thumbnail dimension (420px)
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let decoded = Self.downsample(data: data, maxDimension: MediaCacheManager.standardThumbnailDimension) ?? AnimatedImageDecoder.decode(from: data) else {
                    return nil
                }
                MediaCacheManager.shared.saveThumbnail(decoded, for: diskKey)
                return decoded
            }.value
            
            if let image {
                thumbnailCache.setObject(image, forKey: memoryCacheKey)
            }
            return image
        } catch {
            if !Task.isCancelled {
                AppLog.smb.error("Failed to load thumbnail at \(item.shareName, privacy: .private)/\(item.path, privacy: .private): \(error.localizedDescription)")
            }
            return nil
        }
    }
    
    /// Attempts fast-path prefix thumbnail generation for linearized / web-optimized PDFs.
    ///
    /// Reads only the initial 1 MB prefix of the document. If linearized, Page 1 can be parsed
    /// and rendered immediately without downloading the full document. If non-linearized, returns `nil`
    /// without saturating the SMB socket.
    ///
    /// - Parameters:
    ///   - item: The target PDF `MediaItem`.
    ///   - maxDimension: Maximum thumbnail bounding dimension.
    /// - Returns: A rendered cover `UIImage`, or `nil` if the document is not linearized or read fails.
    func fetchPDFPrefixThumbnail(for item: MediaItem, maxDimension: CGFloat = MediaCacheManager.standardThumbnailDimension) async -> UIImage? {
        let (diskKey, _, _) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: maxDimension,
            connectionID: item.connectionID
        )
        let memoryCacheKey = "\(item.id)_thumb" as NSString
        
        do {
            let client = try await ensureConnected(to: item.shareName)
            if Task.isCancelled { return nil }
            
            let prefixLength: Int64 = min(item.size > 0 ? item.size : 1_048_576, 1_048_576)
            guard prefixLength > 0 else { return nil }
            
            let range: Range<Int64> = 0..<prefixLength
            do {
                let prefixData = try await client.contents(atPath: item.path, range: range) { _, _ in
                    !Task.isCancelled
                }
                if !prefixData.isEmpty,
                   let thumb = MediaCacheManager.shared.generatePDFThumbnail(from: prefixData, maxDimension: maxDimension) {
                    thumbnailCache.setObject(thumb, forKey: memoryCacheKey)
                    MediaCacheManager.shared.saveThumbnail(thumb, for: diskKey)
                    return thumb
                }
            } catch {
                if !Task.isCancelled {
                    AppLog.smb.warning("Fast-path prefix read failed at \(item.shareName, privacy: .private)/\(item.path, privacy: .private): \(error.localizedDescription)")
                }
            }
            return nil
        } catch {
            if !Task.isCancelled {
                AppLog.smb.error("Failed to connect for PDF prefix thumbnail at \(item.shareName, privacy: .private)/\(item.path, privacy: .private): \(error.localizedDescription)")
            }
            return nil
        }
    }
    
    // MARK: - Video & Document Local Caching
    
    /// Streams a video file from SMB directly to disk cache for smooth AVPlayer playback.
    ///
    /// ### Complex Code Breakdown:
    /// - **Atomic Staging**: Downloads to `.part` file. Upon completion, replaces or moves to final destination.
    /// - **LRU Eviction**: Calls `evictVideosIfNeeded` to prevent cache bloating, protecting the newly landed file.
    /// - **Video Thumbnail Upgrading**: Extracts an actual video frame from the downloaded file at 0.5s to replace placeholder icons.
    ///
    /// - Parameters:
    ///   - item: The video `MediaItem`.
    ///   - progress: Optional callback delivering `(bytesDownloaded, totalBytes)`.
    /// - Returns: The local `URL` referencing the cached video file.
    func fetchVideoURL(for item: MediaItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        let localURL = MediaCacheManager.shared.localVideoURL(for: item)
        if MediaCacheManager.shared.hasCachedVideo(for: item) {
            return localURL
        }
        
        let client = try await ensureConnected(to: item.shareName)
        let partURL = localURL.appendingPathExtension("part")
        
        // Remove any dangling partial download from a previous aborted attempt
        try? FileManager.default.removeItem(at: partURL)
        
        do {
            // Stream directly to temporary .part file on disk (atomic download)
            try await client.downloadItem(atPath: item.path, to: partURL) { bytes, total in
                if Task.isCancelled { return false }
                progress?(bytes, total)
                return true
            }
            
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: partURL)
                throw CancellationError()
            }
            
            // Promote temporary .part file to final local video file atomically
            if FileManager.default.fileExists(atPath: localURL.path) {
                do {
                    _ = try FileManager.default.replaceItemAt(localURL, withItemAt: partURL, backupItemName: nil, options: [])
                } catch {
                    try? FileManager.default.removeItem(at: localURL)
                    try FileManager.default.moveItem(at: partURL, to: localURL)
                }
            } else {
                try FileManager.default.moveItem(at: partURL, to: localURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: partURL)
            throw error
        }
        
        // Evict older videos if cache exceeds limit, protecting the newly downloaded one
        MediaCacheManager.shared.evictVideosIfNeeded(keeping: [localURL])
        
        // Upgrade thumbnail cache with real video frame now that it's downloaded
        let (diskKey, _, _) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: "\(item.path)_vidstream_v7",
            dimension: MediaCacheManager.standardThumbnailDimension,
            connectionID: item.connectionID
        )
        if let thumb = await MediaCacheManager.shared.generateVideoThumbnail(
            from: localURL,
            maxDimension: MediaCacheManager.standardThumbnailDimension,
            preferredTime: MediaCacheManager.defaultVideoThumbnailTime
        ) {
            let memoryCacheKey = "\(item.id)_thumb" as NSString
            thumbnailCache.setObject(thumb, forKey: memoryCacheKey)
            MediaCacheManager.shared.saveThumbnail(thumb, for: diskKey)
        }
        
        return localURL
    }
    
    /// Downloads an entire document (e.g. PDF) to persistent local disk cache so `PDFView` can render and search it.
    ///
    /// - Parameters:
    ///   - item: The document `MediaItem`.
    ///   - progress: Optional callback delivering `(bytesDownloaded, totalBytes)`.
    /// - Returns: The local `URL` referencing the cached document file.
    func fetchDocumentURL(for item: MediaItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        let localURL = MediaCacheManager.shared.localDocumentURL(for: item)
        if MediaCacheManager.shared.hasCachedDocument(for: item) {
            return localURL
        }
        
        let client = try await ensureConnected(to: item.shareName)
        let partURL = localURL.appendingPathExtension("part")
        
        try? FileManager.default.removeItem(at: partURL)
        
        do {
            try await client.downloadItem(atPath: item.path, to: partURL) { bytes, total in
                if Task.isCancelled { return false }
                progress?(bytes, total)
                return true
            }
            
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: partURL)
                throw CancellationError()
            }
            
            if FileManager.default.fileExists(atPath: localURL.path) {
                do {
                    _ = try FileManager.default.replaceItemAt(localURL, withItemAt: partURL, backupItemName: nil, options: [])
                } catch {
                    try? FileManager.default.removeItem(at: localURL)
                    try FileManager.default.moveItem(at: partURL, to: localURL)
                }
            } else {
                try FileManager.default.moveItem(at: partURL, to: localURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: partURL)
            throw error
        }
        
        // Evict older documents if cache exceeds limit, protecting the newly downloaded one
        MediaCacheManager.shared.evictDocumentsIfNeeded(keeping: [localURL])
        
        // Upgrade thumbnail cache with rendered PDF cover page
        let (diskKey, _, _) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: MediaCacheManager.standardThumbnailDimension,
            connectionID: item.connectionID
        )
        if let thumb = MediaCacheManager.shared.generatePDFThumbnail(from: localURL, maxDimension: MediaCacheManager.standardThumbnailDimension) {
            let memoryCacheKey = "\(item.id)_thumb" as NSString
            thumbnailCache.setObject(thumb, forKey: memoryCacheKey)
            MediaCacheManager.shared.saveThumbnail(thumb, for: diskKey)
        }
        
        return localURL
    }
    
    /// Flushes all in-memory caches to immediately release RAM upon system low-memory warnings.
    func clearMemoryCache() {
        thumbnailCache.removeAllObjects()
        fullImageCache.removeAllObjects()
        metadataCache.removeAllObjects()
    }
    
    /// Removes memory cached thumbnails matching the specified item identifiers.
    ///
    /// - Parameter itemIDs: The array of `MediaItem.id` strings to evict from RAM.
    func removeThumbnailsFromMemory(for itemIDs: [String]) {
        for id in itemIDs {
            thumbnailCache.removeObject(forKey: "\(id)_thumb" as NSString)
        }
    }
    
    // MARK: - Streaming Media Byte Range Requests
    
    /// Reads a discrete byte range over SMB for on-demand video streaming without downloading full files.
    ///
    /// ### Complex Code Breakdown:
    /// - **Exponential Backoff Retry**: If a socket read fails (broken pipe or timeout), retries up to 3 times
    ///   with increasing backoff delays (250ms, 500ms) and forces tree reconnection.
    /// - **Cancellation Checking**: Immediately halts transfers when `Task.isCancelled` occurs.
    ///
    /// - Parameters:
    ///   - item: The target media item.
    ///   - offset: The zero-based starting byte offset.
    ///   - length: The number of bytes to retrieve.
    /// - Returns: The retrieved raw `Data` payload.
    func fetchMediaRange(for item: MediaItem, offset: Int64, length: Int) async throws -> Data {
        let maxAttempts = 3
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                // If retrying, force reconnecting the share to renew dead or timed-out sockets
                let client = try await ensureConnected(to: item.shareName, forceReconnect: attempt > 1)
                try Task.checkCancellation()
                
                let end = offset + Int64(length)
                let range: Range<Int64> = offset..<end
                return try await client.contents(atPath: item.path, range: range) { _, _ in
                    !Task.isCancelled
                }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
                
                // Exponential backoff before retry: 250ms on first failure, 500ms on second
                if attempt < maxAttempts {
                    let backoffMs = UInt64(attempt * 250)
                    try? await Task.sleep(nanoseconds: backoffMs * 1_000_000)
                }
            }
        }
        
        throw lastError ?? URLError(.cannotConnectToHost)
    }
    
    /// Queries the file size attribute from the server if not populated during directory traversal.
    ///
    /// - Parameter item: The target `MediaItem`.
    /// - Returns: The remote file size in bytes, or 0 if unreachable.
    func fetchFileSize(for item: MediaItem) async -> Int64 {
        if item.size > 0 { return item.size }
        if Task.isCancelled { return 0 }
        do {
            let client = try await ensureConnected(to: item.shareName)
            if Task.isCancelled { return 0 }
            let attrs = try await client.attributesOfItem(atPath: item.path)
            return Self.extractFileSize(from: attrs)
        } catch {
            return 0
        }
    }
    
    /// Safely extracts the 64-bit file size integer from URL resource dictionaries across diverse system representations.
    private static func extractFileSize(from dict: [URLResourceKey: Any]) -> Int64 {
        (dict[.fileSizeKey] as? NSNumber)?.int64Value ?? (dict[.fileSizeKey] as? Int64) ?? (dict[.fileSizeKey] as? Int).map(Int64.init) ?? 0
    }
    
    // MARK: - Full Image & EXIF Metadata Fetching
    
    /// Downloads the full-resolution picture, decoding and caching it in `fullImageCache` for slideshow presentation.
    ///
    /// - Parameter item: The photo `MediaItem` to load.
    /// - Returns: The decoded `UIImage`, or `nil` on failure or cancellation.
    func fetchFullImage(for item: MediaItem) async -> UIImage? {
        // Videos must never be loaded as full images into RAM
        if Task.isCancelled || item.isVideo { return nil }
        
        let cacheKey = "\(item.id)_full" as NSString
        if let cached = fullImageCache.object(forKey: cacheKey) {
            return cached
        }
        
        if Task.isCancelled { return nil }
        
        do {
            let client = try await ensureConnected(to: item.shareName)
            if Task.isCancelled { return nil }
            
            let data = try await client.contents(atPath: item.path) { _, _ in
                !Task.isCancelled
            }
            if Task.isCancelled { return nil }
            
            // Ensure metadata is cached from downloaded full image bytes
            if metadataCache.object(forKey: item.id as NSString) == nil {
                let meta = ImageMetadataExtractor.extract(from: data, fileName: item.name, fileSize: item.formattedSize)
                metadataCache.setObject(PictureEXIFBox(meta), forKey: item.id as NSString)
            }
            
            guard let image = AnimatedImageDecoder.decode(from: data) else { return nil }
            
            // Broken up into distinct sub-expressions to prevent compiler type-checking timeouts
            let widthInPixels = image.size.width * image.scale
            let heightInPixels = image.size.height * image.scale
            let pixelCost = Int(widthInPixels * heightInPixels * 4.0)
            
            fullImageCache.setObject(image, forKey: cacheKey, cost: max(data.count, pixelCost))
            return image
        } catch {
            if !Task.isCancelled {
                AppLog.smb.error("Failed to load full image at \(item.shareName, privacy: .private)/\(item.path, privacy: .private): \(error.localizedDescription)")
            }
            return nil
        }
    }
    
    /// Extracts EXIF and camera metadata for an item.
    ///
    /// ### Complex Code Breakdown:
    /// - **Video Bypass**: Videos return lightweight metadata directly without downloading gigabytes of stream payload.
    /// - **Memory Cache**: Checks `metadataCache` first.
    /// - **64 KB Partial Header Request**: Executes an initial byte-range read (`0..<65536`) to extract EXIF headers.
    ///   If headers are resolved in this first block, returns immediately without downloading the full image.
    /// - **Full Payload Fallback**: Only downloads the complete file if EXIF tags were located further down in the stream.
    ///
    /// - Parameter item: The `MediaItem` to inspect.
    /// - Returns: The extracted `PictureEXIFData`, or `nil` on failure.
    func fetchMetadata(for item: MediaItem) async -> PictureEXIFData? {
        if Task.isCancelled { return nil }
        // For video files, return basic file metadata directly without downloading gigabytes of data into RAM
        if item.isVideo {
            let dateStr = item.modifiedDate?.formatted(date: .abbreviated, time: .shortened)
            return PictureEXIFData(
                fileName: item.name,
                fileSize: item.formattedSize,
                dimensions: nil,
                megapixels: nil,
                cameraModel: nil,
                lensModel: nil,
                focalLength: nil,
                aperture: nil,
                shutterSpeed: nil,
                iso: nil,
                dateTaken: dateStr,
                fileFormat: (item.name as NSString).pathExtension.uppercased()
            )
        }
        
        // 1. Check in-memory metadata cache (populated during thumbnail or full image fetch)
        let cacheKey = item.id as NSString
        if let cached = metadataCache.object(forKey: cacheKey)?.value {
            return cached
        }
        
        do {
            let client = try await ensureConnected(to: item.shareName)
            if Task.isCancelled { return nil }
            
            // 2. Fast single-packet fetch: Read first 64 KB range to extract EXIF header
            let rangeData = try? await client.contents(atPath: item.path, range: 0..<65536) { _, _ in
                !Task.isCancelled
            }
            if let rangeData, !rangeData.isEmpty {
                let meta = ImageMetadataExtractor.extract(from: rangeData, fileName: item.name, fileSize: item.formattedSize)
                if meta.dimensions != nil || meta.cameraModel != nil || meta.dateTaken != nil {
                    metadataCache.setObject(PictureEXIFBox(meta), forKey: cacheKey)
                    return meta
                }
            }
            
            // 3. Fallback to full contents only if EXIF header was located deeper in the file
            if Task.isCancelled { return nil }
            let data = try await client.contents(atPath: item.path) { _, _ in
                !Task.isCancelled
            }
            if Task.isCancelled { return nil }
            let meta = ImageMetadataExtractor.extract(from: data, fileName: item.name, fileSize: item.formattedSize)
            metadataCache.setObject(PictureEXIFBox(meta), forKey: cacheKey)
            return meta
        } catch {
            return nil
        }
    }
    
    // MARK: - CoreGraphics Image Downsampling
    
    /// Downsamples compressed image data directly into a display thumbnail using `ImageIO` and `CoreGraphics`.
    ///
    /// Setting `kCGImageSourceShouldCache: false` prevents the operating system from allocating a full-resolution
    /// backing bitmap in RAM, decoding only the target pixel bounding box specified by `maxDimension`.
    ///
    /// - Parameters:
    ///   - data: Raw encoded image bytes (JPEG, HEIC, PNG).
    ///   - maxDimension: The maximum pixel size for the longest edge.
    /// - Returns: A decoded, downscaled `UIImage`, or `nil` on decode failure.
    private static func downsample(data: Data, maxDimension: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
