//
//  StorageLocationManager.swift
//  fichier
//

import Foundation
import Observation
import UIKit
import AVFoundation
#if canImport(PDFKit) && !os(tvOS)
import PDFKit
#endif
import Wappn
import FichierKit

/// Centralized state manager and coordinator for all media storage backends in the application.
///
/// `StorageLocationManager` is an `@Observable` model object isolated to the `@MainActor`. It coordinates
/// browsing, caching, and streaming across three distinct storage backends:
/// 1. **SMB Network Shares** — Managed via `SMBClientActor` and authenticated via `FichierKit.SMBPasswordStore`.
/// 2. **Local and iCloud Drive Folders** — Managed via `LocalStorageActor` using security-scoped bookmarks.
/// 3. **Apple Photos Library** — Managed via `PhotoLibraryActor` using PhotoKit.
///
/// ### Key Responsibilities
/// - Maintains active connections and persisted credentials for servers and local folders.
/// - Drives navigation through hierarchical folder trees and tracks selected media collections.
/// - Coordinates two-tier in-memory and persistent disk caching for thumbnails and full-resolution media.
/// - Dispatches video thumbnail generation through a bounded concurrency limiter (`FichierKit.SMBVideoThumbnailLimiter`)
///   and custom resource loaders (`FichierKit.SMBAVAssetResourceLoaderDelegate`).
/// - Handles system memory pressure and background lifecycle transitions to avoid out-of-memory (OOM) terminations.
@Observable
@MainActor
public final class StorageLocationManager {
    /// Current discrete connection lifecycle state.
    public var connectionState: StorageLocationConnectionState = .idle
    
    /// Indicates whether a storage location is currently connected and ready for browsing.
    public var isConnected: Bool {
        get {
            if case .connected = connectionState {
                return true
            }
            return false
        }
        set {
            if newValue {
                connectionState = .connected
            } else if connectionState == .connected {
                connectionState = .idle
            }
        }
    }
    
    /// Indicates whether a network request or folder scanning operation is currently in flight.
    public var isLoading: Bool {
        get {
            if case .connecting = connectionState {
                return true
            }
            return isPerformingOperation
        }
        set {
            isPerformingOperation = newValue
            if newValue && connectionState == .idle {
                connectionState = .connecting
            } else if !newValue && connectionState == .connecting {
                connectionState = .idle
            }
        }
    }
    
    /// User-presentable error message from the most recent failed operation, or `nil` if healthy.
    public var errorMessage: String? {
        get {
            if case .failed(let message) = connectionState {
                return message
            }
            return operationErrorMessage
        }
        set {
            operationErrorMessage = newValue
            if let newValue {
                if case .connected = connectionState {
                    // Retain active connection when recording an incidental operation failure
                } else {
                    connectionState = .failed(newValue)
                }
            } else if case .failed = connectionState {
                connectionState = .idle
            }
        }
    }

    private var isPerformingOperation = false
    private var operationErrorMessage: String?
    private var locationSelectionGeneration: UInt64 = 0
    
    /// Persisted list of validated SMB server credentials and connection metadata.
    public var savedConnections: [SavedSMBConnection] = []
    
    /// Persisted list of local and iCloud Drive folder security-scoped bookmarks.
    public var savedFolderLocations: [SavedFolderLocation] = []
    
    /// The currently selected storage location (SMB share, local/iCloud folder, or Photos Library).
    public var currentLocation: StorageLocation?
    
    /// Discovered top-level SMB shares on the currently active connection.
    public var serverShares: [MediaItem] {
        guard currentLocation?.kind == .smb else { return [] }
        return folderTree
    }
    
    /// The currently selected SMB share (root of the displayed folder tree).
    public var selectedShare: MediaItem?
    
    /// Indicates whether a storage drive (SMB share, local/iCloud folder, or Photos library) is actively selected.
    public var hasSelectedDrive: Bool {
        guard isConnected, let location = currentLocation else {
            return false
        }
        if location.kind == .smb {
            return selectedShare != nil
        }
        return true
    }
    
    /// Hierarchical tree of folders and shares used to populate the navigation sidebar.
    ///
    /// Updating this tree automatically recalculates `parentFolder` for O(1) breadcrumb navigation.
    public var folderTree: [MediaItem] = [] {
        didSet {
            updateParentFolder()
        }
    }
    
    /// Immediate child subfolders within the currently selected folder.
    public var currentFolders: [MediaItem] = []
    
    /// The folder currently selected in the sidebar or grid navigation.
    ///
    /// Modifying this property triggers an automatic recalculation of `parentFolder`.
    public var selectedFolder: MediaItem? {
        didSet {
            updateParentFolder()
        }
    }
    
    /// Cached parent folder of the currently selected folder, providing O(1) access for upward navigation.
    public internal(set) var parentFolder: MediaItem?
    
    /// Media items (photos, videos, PDFs) discovered in the currently selected folder.
    public var pictures: [MediaItem] = []
    
    /// The unique identifier of the currently active folder, used to discard stale async thumbnail requests.
    public internal(set) var activeFolderID: String?
    
    /// Identifier representing the current connection session, used for cache partitioning.
    public private(set) var currentConnectionID: String = ""
    
    /// Tracks dynamic thumbnail generation tokens per media item, allowing observing SwiftUI views to react to on-the-fly upgrades.
    public internal(set) var thumbnailVersions: [String: Int] = [:]
    
    /// In-flight asynchronous folder scanning task, cancelled when switching folders rapidly.
    var loadFolderTask: Task<Void, Never>?

    /// Monotonic generation counter rejecting stale folder load commits.
    var folderGeneration: UInt64 = 0
    
    /// In-memory memory map preserving the last viewed folder per location ID for seamless split-view restoration.
    var lastSelectedFolderPerLocation: [String: MediaItem] = [:]
    
    /// Background actor managing SMB connections, directory scanning, and streaming.
    let worker: SMBClientActor
    
    /// Nonisolated accessor exposing the worker actor for background streaming operations.
    nonisolated var clientActor: SMBClientActor { worker }
    
    /// Background actor managing local sandbox and security-scoped file system access.
    let localWorker: LocalStorageActor
    
    /// Background actor managing PhotoKit queries and PHAsset fetching.
    let photosWorker: PhotoLibraryActor
    
    /// Concurrency limiter preventing socket saturation during parallel video keyframe extraction.
    let videoThumbnailLimiter = SMBVideoThumbnailLimiter(maxConcurrent: 2)
    
    #if !os(tvOS)
    /// Concurrency limiter preventing socket saturation during parallel PDF document thumbnail extraction.
    let pdfThumbnailLimiter = SMBVideoThumbnailLimiter(maxConcurrent: 1)
    #endif
    
    /// Persistence store handling SMB credentials and sandboxed folder bookmarks.
    let persistenceStore: StorageLocationPersistenceStore
    
    /// Navigation coordinator handling root boundary checks, mutation revisions, and tree hierarchy derivation.
    public let navigationCoordinator: FolderNavigationCoordinator
    
    /// Relays the current mutation revision from the navigation coordinator.
    public var mutationRevision: Int {
        navigationCoordinator.mutationRevision
    }
    
    /// Signals that a filesystem mutation occurred, bumping the revision counter and refreshing state.
    public func recordMutation() {
        navigationCoordinator.recordMutation()
    }
    
    /// Initializes the manager, restoring saved connections and registering lifecycle observers.
    public convenience init() {
        self.init(
            worker: SMBClientActor(),
            localWorker: LocalStorageActor(),
            photosWorker: PhotoLibraryActor(),
            persistenceStore: StorageLocationPersistenceStore(),
            navigationCoordinator: FolderNavigationCoordinator()
        )
    }

    /// Dependency-injected initializer used internally and by unit tests.
    init(
        worker: SMBClientActor,
        localWorker: LocalStorageActor = LocalStorageActor(),
        photosWorker: PhotoLibraryActor = PhotoLibraryActor(),
        persistenceStore: StorageLocationPersistenceStore = StorageLocationPersistenceStore(),
        navigationCoordinator: FolderNavigationCoordinator = FolderNavigationCoordinator()
    ) {
        self.worker = worker
        self.localWorker = localWorker
        self.photosWorker = photosWorker
        self.persistenceStore = persistenceStore
        self.navigationCoordinator = navigationCoordinator
        loadSavedConnections()
        loadSavedFolderLocations()
        setupLifecycleObservers()
        Task {
            await refreshMediaCacheSize()
        }
    }
    
    // MARK: - Select Unified Location
    
    /// Activates and mounts a storage location, preparing its root folder tree for navigation.
    ///
    /// This method performs clean disconnection from the previous backend, initializes the target
    /// backend actor, and restores the previously selected subfolder if one was recorded in memory.
    ///
    /// - Parameter location: The target location to activate.
    public func selectLocation(_ location: StorageLocation) async {
        locationSelectionGeneration &+= 1
        let currentGen = locationSelectionGeneration

        connectionState = .connecting
        operationErrorMessage = nil

        switch location.kind {
        case .smb:
            guard let conn = location.smbConnection else {
                connectionState = .idle
                return
            }
            await disconnect(resetConnectionState: false)
            guard currentGen == locationSelectionGeneration else { return }
            currentLocation = location
            let pass = await password(for: conn)
            guard currentGen == locationSelectionGeneration else { return }
            await connect(host: conn.host, user: conn.username, pass: pass, hostname: conn.hostname)
            
        case .localFolder, .iCloudFolder:
            guard let folderLoc = location.folderLocation else {
                connectionState = .idle
                return
            }
            await disconnect(resetConnectionState: false)
            guard currentGen == locationSelectionGeneration else { return }
            currentLocation = location
            currentConnectionID = location.id
            
            do {
                let (rootItem, updatedBookmark) = try await localWorker.activateLocation(folderLoc)
                guard currentGen == locationSelectionGeneration else { return }
                if let newBookmark = updatedBookmark {
                    updateBookmarkData(newBookmark, for: folderLoc)
                }
                self.folderTree = [rootItem]
                self.connectionState = .connected
                
                // Restore previously selected folder or default to root
                let locID = location.id
                let targetFolder = lastSelectedFolderPerLocation[locID] ?? rootItem
                await selectAndLoadFolder(targetFolder)
            } catch is CancellationError {
                guard currentGen == locationSelectionGeneration else { return }
                self.connectionState = .idle
            } catch {
                guard currentGen == locationSelectionGeneration else { return }
                self.connectionState = .failed(error.localizedDescription)
            }
            
        case .photos:
            await disconnect(resetConnectionState: false)
            guard currentGen == locationSelectionGeneration else { return }
            currentLocation = location
            currentConnectionID = location.id
            
            do {
                let rootItem = try await photosWorker.activateLocation()
                guard currentGen == locationSelectionGeneration else { return }
                let (albums, _) = try await photosWorker.listContents(at: rootItem)
                guard currentGen == locationSelectionGeneration else { return }
                var rootWithChildren = rootItem
                rootWithChildren.children = albums.isEmpty ? nil : albums
                self.folderTree = [rootWithChildren]
                self.connectionState = .connected
                
                // Restore previously selected album/folder if available
                let locID = location.id
                if let remembered = lastSelectedFolderPerLocation[locID],
                   albums.contains(where: { $0.id == remembered.id }) || remembered.id == rootWithChildren.id {
                    await selectAndLoadFolder(remembered)
                } else if let firstAlbum = albums.first {
                    await selectAndLoadFolder(firstAlbum)
                } else {
                    await selectAndLoadFolder(rootWithChildren)
                }
            } catch is CancellationError {
                guard currentGen == locationSelectionGeneration else { return }
                self.connectionState = .idle
            } catch {
                guard currentGen == locationSelectionGeneration else { return }
                self.connectionState = .failed(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Connect to Mac mini & List All Shares Automatically
    
    /// Connects to a remote SMB server and enumerates its exported shares.
    ///
    /// Sanitizes the input host, constructs session credentials, queries available shares via `SMBClientActor`,
    /// persists successful connections, and auto-selects the first share or previously viewed subfolder.
    ///
    /// - Parameters:
    ///   - host: Hostname or IP address.
    ///   - user: SMB username (empty for guest).
    ///   - pass: Plaintext password.
    ///   - hostname: Optional NetBIOS/Bonjour name for display.
    public func connect(host: String, user: String, pass: String, hostname: String? = nil) async {
        locationSelectionGeneration &+= 1
        let currentGen = locationSelectionGeneration

        folderGeneration &+= 1
        loadFolderTask?.cancel()
        loadFolderTask = nil

        connectionState = .connecting
        operationErrorMessage = nil
        
        let cleanHost = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "smb://", with: "")
            .components(separatedBy: "%").first ?? host
        
        if cleanHost.contains(":") && !cleanHost.hasPrefix("[") {
            connectionState = .failed(String(localized: .Strings.networkingErrorEnterValidAddress))
            return
        }
        
        guard URL(string: "smb://\(cleanHost)") != nil else {
            connectionState = .failed(String(localized: .Strings.networkingErrorInvalidHostUrl))
            return
        }
        
        let server = SavedSMBConnection(host: cleanHost, username: user, lastConnected: Date(), hostname: hostname)
        let connID = server.id
        self.currentConnectionID = connID
        
        do {
            let discoveredShares = try await worker.connectAndListShares(server: server, password: pass, connectionID: connID)
            guard currentGen == locationSelectionGeneration else { return }
            guard !discoveredShares.isEmpty else {
                await worker.disconnect()
                guard currentGen == locationSelectionGeneration else { return }
                connectionState = .failed(String(localized: .Strings.networkingErrorNoSharedFolders))
                currentConnectionID = ""
                folderTree = []
                return
            }
            
            // Connection verified! Save server credentials for future use
            await saveValidatedConnection(host: cleanHost, user: user, pass: pass, hostname: hostname)
            guard currentGen == locationSelectionGeneration else { return }
            if let saved = savedConnections.first(where: { $0.id == server.id }) {
                self.currentLocation = StorageLocation(smb: saved)
            }
            
            self.selectedShare = nil
            self.selectedFolder = nil
            self.activeFolderID = nil
            self.currentFolders = []
            self.pictures = []
            self.folderTree = discoveredShares
            self.connectionState = .connected
        } catch is CancellationError {
            await worker.disconnect()
            guard currentGen == locationSelectionGeneration else { return }
            self.connectionState = .idle
            self.currentConnectionID = ""
            self.folderTree = []
        } catch {
            await worker.disconnect()
            guard currentGen == locationSelectionGeneration else { return }
            self.connectionState = .failed(String(localized: .Strings.networkingErrorConnectionFailed(error.localizedDescription)))
            self.currentConnectionID = ""
            self.folderTree = []
        }
    }
    
    // MARK: - Refresh Shares & Current Folder
    
    /// Refreshes the root tree and reloads the currently selected folder across any active backend.
    public func refreshSharesAndFolders() async {
        errorMessage = nil
        if currentLocation?.kind == .photos {
            isLoading = true
            do {
                let rootItem = try await photosWorker.activateLocation()
                let (albums, _) = try await photosWorker.listContents(at: rootItem)
                var rootWithChildren = rootItem
                rootWithChildren.children = albums.isEmpty ? nil : albums
                self.folderTree = [rootWithChildren]
                self.isLoading = false
                if let current = selectedFolder {
                    await selectAndLoadFolder(current)
                } else if let firstAlbum = albums.first {
                    await selectAndLoadFolder(firstAlbum)
                }
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
            return
        }
        
        if let folderLoc = currentLocation?.folderLocation {
            isLoading = true
            do {
                let (rootItem, updatedBookmark) = try await localWorker.activateLocation(folderLoc)
                if let newBookmark = updatedBookmark {
                    updateBookmarkData(newBookmark, for: folderLoc)
                }
                let existingChildren = self.folderTree.first?.children
                var rootWithPreserved = rootItem
                if let existingChildren {
                    rootWithPreserved.children = existingChildren
                }
                self.folderTree = [rootWithPreserved]
                self.isLoading = false
                if let current = selectedFolder {
                    await selectAndLoadFolder(current)
                } else {
                    await selectAndLoadFolder(rootItem)
                }
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
            return
        }
        
        do {
            let refreshedShares = try await worker.refreshShares()
            let existingChildrenMap = Dictionary(
                self.folderTree.compactMap { share in
                    share.children.map { (share.id, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            self.folderTree = refreshedShares.map { share in
                var updated = share
                if let children = existingChildrenMap[share.id] {
                    updated.children = children
                }
                return updated
            }
            
            if let current = selectedFolder {
                await selectAndLoadFolder(current)
            }
        } catch {
            self.errorMessage = String(localized: .Strings.networkingErrorRefreshSharesFailed(error.localizedDescription))
        }
    }
    

    /// Human-readable formatted string indicating total media cache disk usage.
    public var mediaCacheSize: String = "…"
    
    // MARK: - Disconnect
    
    /// Disconnects from the active storage location and resets all navigation and selection state.
    ///
    /// - Parameter resetConnectionState: Whether to transition `connectionState` to `.idle`. Pass `false`
    ///   when transitioning directly into another connection attempt to avoid transient state flicker.
    public func disconnect(resetConnectionState: Bool = true) async {
        folderGeneration &+= 1
        loadFolderTask?.cancel()
        loadFolderTask = nil
        activeFolderID = nil
        currentConnectionID = ""
        currentLocation = nil
        
        if resetConnectionState {
            connectionState = .idle
        }
        isPerformingOperation = false
        operationErrorMessage = nil
        selectedShare = nil
        folderTree = []
        currentFolders = []
        selectedFolder = nil
        pictures = []
        
        await localWorker.deactivateCurrentLocation()
        await worker.setActiveFolder(id: nil)
        await worker.disconnect()
    }
}
