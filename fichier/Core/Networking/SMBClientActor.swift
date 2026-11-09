//
//  SMBClientActor.swift
//  fichier
//

import Foundation
import UIKit
import CoreGraphics
import ImageIO
import AVFoundation
import OSLog
import FichierKit

/// A serialized network actor responsible for coordinating all low-level SMB2/3 operations.
///
/// ### Architecture & Concurrency Overview
/// - **FichierKit Delegation**: Delegates SMB2/3 share discovery, directory enumeration, file reading,
///   byte-range streaming, and `.part` downloads to `FichierKit`'s `SMBClientProtocol` (`AMSMB2Client`)
///   and `SharesMediaSource`.
/// - **Lockless Synchronous Thumbnail Lookups**: Exposes `thumbnailCache` as `nonisolated` via `ThreadSafeMemoryCache`
///   so SwiftUI rendering passes can query cached images synchronously without awaiting the actor's busy I/O mailbox.
/// - **Atomic Persistence**: Large video and document downloads stream to ephemeral `.part` files on disk and are promoted
///   atomically to their destination paths once integrity and cancellation checks pass.
/// - **Zero-Full-Download EXIF Streaming**: Extracts photo metadata by issuing a 64 KB prefix request over SMB, bypassing
///   multi-megabyte full-file downloads.
actor SMBClientActor {

    // MARK: - Pagination Constants

    /// Default bounded page size when enumerating top-level SMB shares.
    static let defaultSharePageSize: Int = 50

    /// Maximum number of share pages fetched in one pass to prevent infinite cursor loops.
    static let maxSharePages: Int = 20

    /// Default bounded page size for SMB folder contents.
    static let defaultFolderPageSize: Int = 100

    /// Maximum number of subfolder pages scanned during sidebar tree expansion.
    static let maxSubfolderPages: Int = 50

    // MARK: - State Properties

    /// Factory constructing an `SMBClientProtocol` session (defaults to `FichierKit.AMSMB2Client`).
    private let clientFactory: @Sendable (SavedSMBConnection, String) -> any SMBClientProtocol

    /// The active `SMBClientProtocol` client managing the underlying SMB session state.
    private var client: (any SMBClientProtocol)?

    /// Active server connection metadata for constructing `SharesMediaSource` requests.
    private var activeServer: SavedSMBConnection?

    /// The unique identifier of the currently connected saved server configuration.
    private var currentConnectionID: String = ""

    /// Active directory identifier used to cancel or drop out-of-date thumbnail requests when the user rapidly switches folders.
    private var activeFolderID: String?

    /// Monotonic session counter guarding against actor reentrancy races across connect, replace, and disconnect.
    private var sessionGeneration: UInt64 = 0

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

    // MARK: - Initialization

    /// Initializes the SMB client actor with an optional client factory for dependency injection in tests.
    init(
        clientFactory: @escaping @Sendable (SavedSMBConnection, String) -> any SMBClientProtocol = { server, password in
            AMSMB2Client(server: server, password: password)
        }
    ) {
        self.clientFactory = clientFactory
    }

    /// Exposes the currently connected `SMBClientProtocol` instance for shared package streaming delegates.
    func activeClient() -> (any SMBClientProtocol)? {
        client
    }

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

    /// Connects to an SMB host via `FichierKit`, validates credentials, and enumerates non-hidden shared volumes.
    ///
    /// - Parameters:
    ///   - server: Server connection configuration.
    ///   - password: SMB plaintext password.
    ///   - connectionID: Stable identifier scoping cache keys and `MediaItem.id`.
    ///   - sharePageSize: Bounded page size used while enumerating server shares.
    /// - Returns: A sorted list of root directory `MediaItem` instances.
    func connectAndListShares(
        server: SavedSMBConnection,
        password: String,
        connectionID: String = "",
        sharePageSize: Int = SMBClientActor.defaultSharePageSize
    ) async throws -> [MediaItem] {
        sessionGeneration &+= 1
        let expectedGeneration = sessionGeneration

        let previousClient = client
        clearSessionState()
        await Self.disconnectClient(previousClient)

        try Task.checkCancellation()
        guard sessionGeneration == expectedGeneration else {
            throw CancellationError()
        }

        let resolvedConnectionID = connectionID.isEmpty ? server.id : connectionID
        let newClient = clientFactory(server, password)
        let sharesSource = SharesMediaSource(server: server, client: newClient)

        do {
            let sourceItems = try await fetchAllBoundedShares(from: sharesSource, pageSize: sharePageSize)

            guard !Task.isCancelled, sessionGeneration == expectedGeneration else {
                await Self.disconnectClient(newClient)
                if sessionGeneration == expectedGeneration {
                    clearSessionState()
                }
                throw CancellationError()
            }

            guard !sourceItems.isEmpty else {
                await Self.disconnectClient(newClient)
                if sessionGeneration == expectedGeneration {
                    clearSessionState()
                }
                return []
            }

            self.client = newClient
            self.activeServer = server
            self.currentConnectionID = resolvedConnectionID

            return sourceItems.map { sourceItem in
                MediaItem(
                    sourceItem: sourceItem,
                    locationID: resolvedConnectionID,
                    rootName: sourceItem.smbShare ?? sourceItem.name
                )
            }
        } catch {
            await Self.disconnectClient(newClient)
            if sessionGeneration == expectedGeneration {
                clearSessionState()
            }
            throw error
        }
    }

    /// Refreshes the list of available shares on the currently active connection.
    ///
    /// - Parameter pageSize: Bounded page size used while enumerating server shares.
    /// - Returns: An updated list of root shares.
    /// - Throws: `URLError(.notConnectedToInternet)` if no client session is currently active.
    func refreshShares(pageSize: Int = SMBClientActor.defaultSharePageSize) async throws -> [MediaItem] {
        try Task.checkCancellation()
        let expectedGeneration = sessionGeneration
        guard let client, let activeServer else {
            throw URLError(.notConnectedToInternet)
        }
        let connID = self.currentConnectionID
        let sharesSource = SharesMediaSource(server: activeServer, client: client)
        let sourceItems = try await fetchAllBoundedShares(from: sharesSource, pageSize: pageSize)
        try Task.checkCancellation()
        guard sessionGeneration == expectedGeneration else {
            throw CancellationError()
        }
        return sourceItems.map { sourceItem in
            MediaItem(
                sourceItem: sourceItem,
                locationID: connID,
                rootName: sourceItem.smbShare ?? sourceItem.name
            )
        }
    }

    /// Disconnects from the current SMB session and purges all in-memory image and metadata caches.
    func disconnect() async {
        sessionGeneration &+= 1
        let activeClient = client
        clearSessionState()
        await Self.disconnectClient(activeClient)
    }

    /// Resets session metadata and volatile memory caches synchronously on the actor executor.
    private func clearSessionState() {
        client = nil
        activeServer = nil
        currentConnectionID = ""
        activeFolderID = nil
        clearMemoryCache()
    }

    /// Disconnects a `SMBClientProtocol` instance in an uncancelled task so teardown runs even under task cancellation.
    private nonisolated static func disconnectClient(_ targetClient: (any SMBClientProtocol)?) async {
        guard let targetClient else { return }
        await Task {
            await targetClient.disconnect()
        }.value
    }

    /// Fetches all shares using bounded pages via `SharesMediaSource.fetchDirectoryPage` instead of `Int.max`.
    private func fetchAllBoundedShares(
        from sharesSource: SharesMediaSource,
        pageSize: Int
    ) async throws -> [MediaSourceItem] {
        let boundedPageSize = max(1, pageSize)
        var collected: [MediaSourceItem] = []
        var seenIDs: Set<String> = []
        var cursor: String?

        for _ in 0..<Self.maxSharePages {
            try Task.checkCancellation()
            let page = try await sharesSource.fetchDirectoryPage(
                in: nil,
                sortBy: .name,
                order: .ascending,
                cursor: cursor,
                pageSize: boundedPageSize
            )
            try Task.checkCancellation()

            for item in page.items where seenIDs.insert(item.id).inserted {
                collected.append(item)
            }

            guard let nextCursor = page.nextCursor,
                  nextCursor != cursor,
                  !page.items.isEmpty else {
                break
            }
            cursor = nextCursor
        }

        return collected
    }

    // MARK: - Directory Enumeration

    /// Scans a single bounded page of directory entries within a share via `FichierKit`.
    ///
    /// - Parameters:
    ///   - shareName: The name of the share volume.
    ///   - path: The directory path relative to the share root.
    ///   - cursor: Opaque continuation cursor from a previous `SMBFolderPage`, or `nil` for the first page.
    ///   - pageSize: Maximum number of items requested for this page.
    ///   - sortKey: Global sort key forwarded to `FichierKit`.
    ///   - sortOrder: Global sort direction forwarded to `FichierKit`.
    /// - Returns: A bounded `SMBFolderPage` containing folder-first items and continuation metadata.
    ///
    /// FichierKit bounds the results exposed to the app, but AMSMB2's public API
    /// materializes one complete directory snapshot before paging. This is required
    /// for deterministic global sorting because SMB2 does not provide server-side
    /// sorted cursors or incremental enumeration through the supported API.
    func scanFolderPage(
        shareName: String,
        at path: String,
        cursor: String? = nil,
        pageSize: Int = SMBClientActor.defaultFolderPageSize,
        sortBy sortKey: MediaSortKey = .name,
        order sortOrder: MediaSortOrder = .ascending
    ) async throws -> SMBFolderPage {
        try Task.checkCancellation()
        let expectedGeneration = sessionGeneration
        guard let client, let activeServer else {
            throw URLError(.notConnectedToInternet)
        }

        let cleanRelativePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let connID = self.currentConnectionID
        let folderSourceItem = MediaSourceItem(
            id: "\(connID)|\(shareName)::/\(cleanRelativePath)",
            name: (cleanRelativePath as NSString).lastPathComponent,
            path: cleanRelativePath.isEmpty ? shareName : "\(shareName)/\(cleanRelativePath)",
            type: .folder,
            sourceID: connID,
            smbShare: shareName,
            smbPath: cleanRelativePath
        )

        let boundedPageSize = max(1, pageSize)
        let sharesSource = SharesMediaSource(server: activeServer, client: client)
        let directoryPage = try await sharesSource.fetchDirectoryPage(
            in: folderSourceItem,
            sortBy: sortKey,
            order: sortOrder,
            cursor: cursor,
            pageSize: boundedPageSize
        )

        try Task.checkCancellation()
        guard sessionGeneration == expectedGeneration else {
            throw CancellationError()
        }

        var folders: [MediaItem] = []
        var pictures: [MediaItem] = []

        for sourceItem in directoryPage.items {
            if Task.isCancelled { throw CancellationError() }
            let mapped = MediaItem(
                sourceItem: sourceItem,
                locationID: connID,
                rootName: shareName
            )
            if mapped.isDirectory {
                folders.append(mapped)
            } else {
                pictures.append(mapped)
            }
        }

        return SMBFolderPage(
            folders: folders,
            pictures: pictures,
            nextCursor: directoryPage.nextCursor,
            totalCount: directoryPage.totalCount
        )
    }

    /// Scans immediate subfolders within a directory for sidebar tree expansion without loading trailing media pages.
    ///
    /// - Parameters:
    ///   - shareName: The name of the share volume.
    ///   - path: The directory path relative to the share root.
    ///   - pageSize: Bounded page size per request.
    /// - Returns: Subfolder `MediaItem` entries sorted alphabetically.
    func scanSubfolders(
        shareName: String,
        at path: String,
        pageSize: Int = SMBClientActor.defaultFolderPageSize
    ) async throws -> [MediaItem] {
        let boundedPageSize = max(1, pageSize)
        var collectedFolders: [MediaItem] = []
        var seenIDs: Set<String> = []
        var cursor: String?

        for _ in 0..<Self.maxSubfolderPages {
            try Task.checkCancellation()
            let page = try await scanFolderPage(
                shareName: shareName,
                at: path,
                cursor: cursor,
                pageSize: boundedPageSize,
                sortBy: .name,
                order: .ascending
            )
            try Task.checkCancellation()

            for folder in page.folders where seenIDs.insert(folder.id).inserted {
                collectedFolders.append(folder)
            }

            if !page.pictures.isEmpty {
                break
            }
            guard let nextCursor = page.nextCursor,
                  nextCursor != cursor,
                  !page.folders.isEmpty else {
                break
            }
            cursor = nextCursor
        }

        return collectedFolders
    }

    // MARK: - Thumbnail Retrieval & Downsampling

    /// Fetches and downsamples a media thumbnail using a 2-tier caching hierarchy (RAM + Disk).
    ///
    /// - Parameters:
    ///   - item: The target `MediaItem`.
    ///   - expectedFolderID: The folder ID at the time the request was dispatched.
    ///   - maxDimension: Maximum pixel dimension for the rendered thumbnail.
    /// - Returns: A downsampled `UIImage`, or `nil` on failure or cancellation.
    func fetchThumbnail(
        for item: MediaItem,
        expectedFolderID: String? = nil,
        maxDimension: CGFloat = MediaCacheManager.standardThumbnailDimension
    ) async -> UIImage? {
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

        guard let client else { return nil }

        do {
            // Remote PDF: Fast-path prefix thumbnailing with bounded fallback
            if item.isPDF {
                if let prefixThumb = await fetchPDFPrefixThumbnail(for: item, maxDimension: maxDimension) {
                    return prefixThumb
                }

                // Fallback for non-linearized documents: fetch full document if within safe bounded size (<= 12 MB)
                // to prevent socket starvation during gallery browsing
                let fileSize = item.size > 0 ? item.size : await fetchFileSize(for: item)
                let maxDirectDownloadBytes: Int64 = 12 * 1024 * 1024
                if fileSize > 0 && fileSize <= maxDirectDownloadBytes {
                    do {
                        let localURL = try await fetchDocumentURL(for: item)
                        if let cachedThumb = thumbnailCache.object(forKey: memoryCacheKey) ?? MediaCacheManager.shared.getThumbnail(for: diskKey) {
                            return cachedThumb
                        }
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

            // Photo Thumbnail Handling via FichierKit SMBClientProtocol
            let data = try await client.readFileData(share: item.shareName, path: item.smbRelativePath, maxBytes: nil)
            if Task.isCancelled { return nil }
            if let expected = expectedFolderID, let active = activeFolderID, expected != active {
                return nil
            }

            // Extract and cache metadata immediately while image bytes are in memory
            if metadataCache.object(forKey: item.id as NSString) == nil {
                let meta = ImageMetadataExtractor.extract(from: data, fileName: item.name, fileSize: item.formattedSize)
                metadataCache.setObject(PictureEXIFBox(meta), forKey: item.id as NSString)
            }

            // Offload CPU-bound image downsampling and disk caching off the actor lock
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
    /// and rendered immediately without downloading the full document.
    func fetchPDFPrefixThumbnail(for item: MediaItem, maxDimension: CGFloat = MediaCacheManager.standardThumbnailDimension) async -> UIImage? {
        let (diskKey, fallbackKey, legacyKey) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: maxDimension,
            connectionID: item.connectionID
        )
        let memoryCacheKey = "\(item.id)_thumb" as NSString

        // 1. In-memory RAM Cache check
        if let memoryCached = thumbnailCache.object(forKey: memoryCacheKey) {
            return memoryCached
        }

        // 2. Persistent On-Disk Cache check
        if let diskCached = MediaCacheManager.shared.getThumbnail(for: diskKey, fallbackKey: fallbackKey, legacyKey: legacyKey) {
            thumbnailCache.setObject(diskCached, forKey: memoryCacheKey)
            return diskCached
        }

        guard let client, !Task.isCancelled else { return nil }

        // Resolve actual file size to avoid out-of-bounds prefix requests on small files
        var fileSize = item.size
        if fileSize <= 0 {
            fileSize = await fetchFileSize(for: item)
        }
        guard fileSize > 0 else { return nil }

        let prefixLength: Int64 = min(fileSize, 1_048_576)
        do {
            let prefixData = try await client.readFileData(share: item.shareName, path: item.smbRelativePath, maxBytes: prefixLength)
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
    }

    // MARK: - Video & Document Local Caching

    /// Streams a video file from SMB directly to disk cache via `.part` staging.
    func fetchVideoURL(for item: MediaItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        let localURL = MediaCacheManager.shared.localVideoURL(for: item)
        if MediaCacheManager.shared.hasCachedVideo(for: item) {
            return localURL
        }

        guard let client else {
            throw URLError(.notConnectedToInternet)
        }
        let partURL = localURL.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partURL)

        do {
            try await client.downloadFile(share: item.shareName, path: item.smbRelativePath, to: partURL) { bytes, total in
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

        // Evict older videos if cache exceeds limit, protecting the newly downloaded one
        MediaCacheManager.shared.evictVideosIfNeeded(keeping: [localURL])

        // Upgrade thumbnail cache with real video frame now that it is downloaded
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

    /// Downloads an entire document (e.g. PDF) to persistent local disk cache via `.part` staging.
    func fetchDocumentURL(for item: MediaItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        let localURL = MediaCacheManager.shared.localDocumentURL(for: item)
        if MediaCacheManager.shared.hasCachedDocument(for: item) {
            return localURL
        }

        guard let client else {
            throw URLError(.notConnectedToInternet)
        }
        let partURL = localURL.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partURL)

        do {
            try await client.downloadFile(share: item.shareName, path: item.smbRelativePath, to: partURL) { bytes, total in
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

    /// Reads a discrete byte range over SMB via `FichierKit.SMBClientProtocol`.
    func fetchMediaRange(for item: MediaItem, offset: Int64, length: Int) async throws -> Data {
        try Task.checkCancellation()
        guard let client else {
            throw URLError(.notConnectedToInternet)
        }
        return try await client.readMediaRange(
            share: item.shareName,
            path: item.smbRelativePath,
            offset: offset,
            length: length
        )
    }

    /// Queries the file size attribute from the server if not populated during directory traversal.
    func fetchFileSize(for item: MediaItem) async -> Int64 {
        if item.size > 0 { return item.size }
        if Task.isCancelled { return 0 }
        guard let client else { return 0 }
        do {
            return try await client.fileSize(share: item.shareName, path: item.smbRelativePath)
        } catch {
            return 0
        }
    }

    // MARK: - Full Image & EXIF Metadata Fetching

    /// Downloads the full-resolution picture, decoding and caching it in `fullImageCache` for slideshow presentation.
    func fetchFullImage(for item: MediaItem) async -> UIImage? {
        if Task.isCancelled || item.isVideo { return nil }

        let cacheKey = "\(item.id)_full" as NSString
        if let cached = fullImageCache.object(forKey: cacheKey) {
            return cached
        }

        guard let client, !Task.isCancelled else { return nil }

        do {
            let data = try await client.readFileData(share: item.shareName, path: item.smbRelativePath, maxBytes: nil)
            if Task.isCancelled { return nil }

            // Ensure metadata is cached from downloaded full image bytes
            if metadataCache.object(forKey: item.id as NSString) == nil {
                let meta = ImageMetadataExtractor.extract(from: data, fileName: item.name, fileSize: item.formattedSize)
                metadataCache.setObject(PictureEXIFBox(meta), forKey: item.id as NSString)
            }

            guard let image = AnimatedImageDecoder.decode(from: data) else { return nil }

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

    /// Extracts EXIF and camera metadata for an item using a 64 KB header range read before full-file fallback.
    func fetchMetadata(for item: MediaItem) async -> PictureEXIFData? {
        if Task.isCancelled { return nil }
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

        let cacheKey = item.id as NSString
        if let cached = metadataCache.object(forKey: cacheKey)?.value {
            return cached
        }

        guard let client else { return nil }

        do {
            // Fast single-packet fetch: Read first 64 KB prefix to extract EXIF header
            let rangeData = try? await client.readFileData(share: item.shareName, path: item.smbRelativePath, maxBytes: 65536)
            if let rangeData, !rangeData.isEmpty {
                let meta = ImageMetadataExtractor.extract(from: rangeData, fileName: item.name, fileSize: item.formattedSize)
                if meta.dimensions != nil || meta.cameraModel != nil || meta.dateTaken != nil {
                    metadataCache.setObject(PictureEXIFBox(meta), forKey: cacheKey)
                    return meta
                }
            }

            if Task.isCancelled { return nil }
            let data = try await client.readFileData(share: item.shareName, path: item.smbRelativePath, maxBytes: nil)
            if Task.isCancelled { return nil }
            let meta = ImageMetadataExtractor.extract(from: data, fileName: item.name, fileSize: item.formattedSize)
            metadataCache.setObject(PictureEXIFBox(meta), forKey: cacheKey)
            return meta
        } catch {
            return nil
        }
    }

    // MARK: - CoreGraphics Image Downsampling

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
