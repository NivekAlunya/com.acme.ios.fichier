//
//  SMBClientActor.swift
//  fichier
//

import Foundation
import UIKit
import CoreGraphics
import ImageIO
import AVFoundation
import Wappn
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

    // MARK: - Share Enumeration Constants

    /// Default bounded page size when enumerating top-level SMB shares.
    static let defaultSharePageSize: Int = 50

    /// Maximum number of share pages fetched in one pass to prevent infinite cursor loops.
    static let maxSharePages: Int = 20

    /// Maximum byte limit when reading photo data for thumbnail generation (25 MB).
    static let maxThumbnailDownloadBytes: Int64 = 25 * 1024 * 1024

    // MARK: - State Properties

    /// Factory constructing an `SMBClientProtocol` session (defaults to `FichierKit.AMSMB2Client`).
    private let clientFactory: @Sendable (SavedSMBConnection, String) -> any SMBClientProtocol

    /// The active `SMBClientProtocol` client managing the underlying SMB session state.
    var client: (any SMBClientProtocol)?

    /// Active server connection metadata for constructing `SharesMediaSource` requests.
    private var activeServer: SavedSMBConnection?

    /// The unique identifier of the currently connected saved server configuration.
    var currentConnectionID: String = ""

    /// Active directory identifier used to cancel or drop out-of-date thumbnail requests when the user rapidly switches folders.
    var activeFolderID: String?

    /// Monotonic session counter guarding against actor reentrancy races across connect, replace, and disconnect.
    private var sessionGeneration: UInt64 = 0

    /// High-performance thread-safe in-memory cache for downsampled thumbnails.
    /// Marked `nonisolated` to allow instant, non-blocking synchronous cache hits on the main thread.
    nonisolated let thumbnailCache = ThreadSafeMemoryCache<NSString, UIImage>()

    /// Bounded in-memory cache for full-resolution pictures, sized dynamically according to physical system RAM.
    let fullImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 5
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        // Dynamically scale in-memory cache limit on low-RAM devices (~187 MB on 3 GB hardware) while capping at 250 MB on 4+ GB devices
        cache.totalCostLimit = Int(min(Int64(250 * 1024 * 1024), Int64(physicalMemory / 16)))
        return cache
    }()

    /// In-memory cache storing parsed EXIF metadata boxes indexed by `MediaItem.id`.
    let metadataCache = NSCache<NSString, PictureEXIFBox>()

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

    /// Exposes the active SMB server connection metadata for streaming options and credentials lookup.
    func activeServerConnection() -> SavedSMBConnection? {
        activeServer
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
        thumbnailCache.removeAllObjects()
        fullImageCache.removeAllObjects()
        metadataCache.removeAllObjects()
    }

    /// Disconnects a `SMBClientProtocol` instance inside an unstructured `Task`.
    ///
    /// `Task {}` does not inherit cooperative cancellation from the calling task while preserving task-local
    /// context, ensuring client teardown runs to completion even when triggered from a cancelled caller.
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

    /// Scans a directory within a specific share via `FichierKit` and segregates entries into subfolders and supported media files.
    ///
    /// - Parameters:
    ///   - shareName: The name of the share volume.
    ///   - path: The directory path relative to the share root.
    /// - Returns: A tuple containing sorted subfolders and media items.
    /// - Throws: `CancellationError` if cancelled, or `SMBError` / `URLError` on network failure.
    func scanFolder(
        shareName: String,
        at path: String
    ) async throws -> (folders: [MediaItem], pictures: [MediaItem]) {
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

        let sharesSource = SharesMediaSource(server: activeServer, client: client)
        let sourceItems = try await sharesSource.fetchItems(
            in: folderSourceItem,
            sortBy: .name,
            order: .ascending,
            page: 0,
            pageSize: Int.max
        )

        try Task.checkCancellation()
        guard sessionGeneration == expectedGeneration else {
            throw CancellationError()
        }

        let (folders, pictures) = try sourceItems.reduce(into: ([MediaItem](), [MediaItem]())) { result, sourceItem in
            if Task.isCancelled { throw CancellationError() }
            let mapped = MediaItem(sourceItem: sourceItem, locationID: connID, rootName: shareName)
            if mapped.isDirectory {
                result.0.append(mapped)
            } else {
                result.1.append(mapped)
            }
        }

        return (folders, pictures)
    }

}
