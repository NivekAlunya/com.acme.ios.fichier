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
import OSLog
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
    /// Indicates whether a storage location is currently connected and ready for browsing.
    public var isConnected = false
    
    /// Indicates whether a network request or folder scanning operation is currently in flight.
    public var isLoading = false
    
    /// User-presentable error message from the most recent failed operation, or `nil` if healthy.
    public var errorMessage: String?
    
    /// Persisted list of validated SMB server credentials and connection metadata.
    public var savedConnections: [SavedSMBConnection] = []
    
    /// Persisted list of local and iCloud Drive folder security-scoped bookmarks.
    public var savedFolderLocations: [SavedFolderLocation] = []
    
    /// The currently selected storage location (SMB share, local/iCloud folder, or Photos Library).
    public var currentLocation: StorageLocation?
    
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
    public private(set) var parentFolder: MediaItem?
    
    /// Media items (photos, videos, PDFs) discovered in the currently selected folder.
    public var pictures: [MediaItem] = []
    
    /// The unique identifier of the currently active folder, used to discard stale async thumbnail requests.
    public private(set) var activeFolderID: String?
    
    /// Identifier representing the current connection session, used for cache partitioning.
    public private(set) var currentConnectionID: String = ""
    
    /// Tracks dynamic thumbnail generation tokens per media item, allowing observing SwiftUI views to react to on-the-fly upgrades.
    public internal(set) var thumbnailVersions: [String: Int] = [:]
    
    /// In-flight asynchronous folder scanning task, cancelled when switching folders rapidly.
    private var loadFolderTask: Task<Void, Never>?

    /// Monotonic generation counter rejecting stale folder load commits.
    private var folderGeneration: UInt64 = 0
    
    /// In-memory memory map preserving the last viewed folder per location ID for seamless split-view restoration.
    private var lastSelectedFolderPerLocation: [String: MediaItem] = [:]
    
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
    private let persistenceStore: StorageLocationPersistenceStore
    
    /// Navigation coordinator handling root boundary checks and tree hierarchy derivation.
    private let navigationCoordinator: FolderNavigationCoordinator
    
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
    
    // MARK: - Lifecycle & Memory Pressure Observers
    
    /// Registers system observers for memory warnings and background transitions.
    ///
    /// To ensure the app maintains a lean memory footprint and complies with iOS memory budgets:
    /// - `didReceiveMemoryWarningNotification` flushes volatile RAM caches in `worker`.
    /// - `didEnterBackgroundNotification` triggers a detached utility task to prune expired disk cache entries.
    private func setupLifecycleObservers() {
        // Clear in-memory image caches on low memory warnings to prevent OOM terminations
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.worker.clearMemoryCache()
            }
        }
        
        // Execute disk cache hygiene sweep when app transitions to background
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task.detached(priority: .utility) {
                MediaCacheManager.shared.performMaintenanceSweep()
            }
        }
    }
    
    // MARK: - Saved Connections Persistence
    
    /// Loads and decodes persisted SMB connections from `UserDefaults`.
    private func loadSavedConnections() {
        savedConnections = persistenceStore.loadSavedConnections()
    }
    
    /// Retrieves the stored password from the secure Keychain for a given SMB connection.
    ///
    /// - Parameter connection: The saved connection metadata.
    /// - Returns: The decrypted password, or an empty string if missing.
    public func password(for connection: SavedSMBConnection) async -> String {
        await persistenceStore.password(for: connection)
    }
    
    /// Stores or updates a validated SMB connection record in `UserDefaults` and saves its password to the Keychain.
    ///
    /// - Parameters:
    ///   - host: Network hostname or IP address.
    ///   - user: Authentication username.
    ///   - pass: Plaintext password to store in Keychain.
    ///   - hostname: Optional Bonjour or NetBIOS display hostname.
    private func saveValidatedConnection(host: String, user: String, pass: String, hostname: String? = nil) async {
        savedConnections = await persistenceStore.saveValidatedConnection(
            host: host,
            user: user,
            pass: pass,
            hostname: hostname,
            existingConnections: savedConnections
        )
    }
    
    /// Deletes a saved connection record from `UserDefaults` and removes its password from Keychain.
    ///
    /// - Parameter connection: The connection to remove.
    public func removeSavedConnection(_ connection: SavedSMBConnection) async {
        savedConnections = await persistenceStore.removeSavedConnection(connection, from: savedConnections)
        if currentLocation?.smbConnection?.id == connection.id {
            Task {
                await disconnect()
            }
        }
    }
    
    // MARK: - Saved Folder Locations Persistence (Local & iCloud Drive)
    
    /// Aggregated list of all available storage locations, ordered with Photos first, followed by folders and SMB servers.
    public var allLocations: [StorageLocation] {
        var list: [StorageLocation] = [StorageLocation.photos]
        for folder in savedFolderLocations {
            list.append(StorageLocation(folder: folder))
        }
        for conn in savedConnections {
            list.append(StorageLocation(smb: conn))
        }
        return list
    }
    
    /// Loads and decodes local folder bookmarks from `UserDefaults`.
    private func loadSavedFolderLocations() {
        savedFolderLocations = persistenceStore.loadSavedFolderLocations()
    }
    
    /// Appends or updates a saved local folder location and persists it to `UserDefaults`.
    ///
    /// - Parameter location: The folder location record containing security-scoped bookmark data.
    public func addSavedFolderLocation(_ location: SavedFolderLocation) {
        savedFolderLocations = persistenceStore.addSavedFolderLocation(location, into: savedFolderLocations)
    }
    
    /// Removes a saved local folder location from `UserDefaults` and disconnects if it is active.
    ///
    /// - Parameter location: The folder location to remove.
    public func removeSavedFolderLocation(_ location: SavedFolderLocation) {
        savedFolderLocations = persistenceStore.removeSavedFolderLocation(location, from: savedFolderLocations)
        if currentLocation?.folderLocation?.id == location.id {
            Task {
                await disconnect()
            }
        }
    }
    
    /// Updates refreshed security-scoped bookmark data for an existing folder location.
    ///
    /// - Parameters:
    ///   - bookmarkData: The updated binary bookmark data.
    ///   - folderLocation: The target location record.
    private func updateBookmarkData(_ bookmarkData: Data, for folderLocation: SavedFolderLocation) {
        savedFolderLocations = persistenceStore.updateBookmarkData(
            bookmarkData,
            for: folderLocation,
            in: savedFolderLocations
        )
    }
    
    /// Dispatches location deletion to the appropriate backend store.
    ///
    /// - Parameter location: The storage location to remove.
    public func removeLocation(_ location: StorageLocation) async {
        switch location.kind {
        case .smb:
            if let smb = location.smbConnection {
                await removeSavedConnection(smb)
            }
        case .localFolder, .iCloudFolder:
            if let folder = location.folderLocation {
                removeSavedFolderLocation(folder)
            }
        case .photos:
            break
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
        switch location.kind {
        case .smb:
            guard let conn = location.smbConnection else { return }
            await disconnect()
            currentLocation = location
            let pass = await password(for: conn)
            await connect(host: conn.host, user: conn.username, pass: pass, hostname: conn.hostname)
            
        case .localFolder, .iCloudFolder:
            guard let folderLoc = location.folderLocation else { return }
            await disconnect()
            isLoading = true
            errorMessage = nil
            currentLocation = location
            currentConnectionID = location.id
            
            do {
                let (rootItem, updatedBookmark) = try await localWorker.activateLocation(folderLoc)
                if let newBookmark = updatedBookmark {
                    updateBookmarkData(newBookmark, for: folderLoc)
                }
                self.folderTree = [rootItem]
                self.isConnected = true
                self.isLoading = false
                
                // Restore previously selected folder or default to root
                let locID = location.id
                let targetFolder = lastSelectedFolderPerLocation[locID] ?? rootItem
                await selectAndLoadFolder(targetFolder)
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
            
        case .photos:
            await disconnect()
            isLoading = true
            errorMessage = nil
            currentLocation = location
            currentConnectionID = location.id
            
            do {
                let rootItem = try await photosWorker.activateLocation()
                let (albums, _) = try await photosWorker.listContents(at: rootItem)
                var rootWithChildren = rootItem
                rootWithChildren.children = albums.isEmpty ? nil : albums
                self.folderTree = [rootWithChildren]
                self.isConnected = true
                self.isLoading = false
                
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
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
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
        folderGeneration &+= 1
        loadFolderTask?.cancel()
        loadFolderTask = nil

        isLoading = true
        errorMessage = nil
        
        let cleanHost = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "smb://", with: "")
            .components(separatedBy: "%").first ?? host
        
        if cleanHost.contains(":") && !cleanHost.hasPrefix("[") {
            errorMessage = String(localized: .Strings.networkingErrorEnterValidAddress)
            isLoading = false
            return
        }
        
        guard URL(string: "smb://\(cleanHost)") != nil else {
            errorMessage = String(localized: .Strings.networkingErrorInvalidHostUrl)
            isLoading = false
            return
        }
        
        let connID = user.isEmpty ? cleanHost : "\(user)@\(cleanHost)"
        self.currentConnectionID = connID
        let server = SavedSMBConnection(host: cleanHost, username: user, lastConnected: Date(), hostname: hostname)
        
        do {
            let discoveredShares = try await worker.connectAndListShares(server: server, password: pass, connectionID: connID)
            guard !discoveredShares.isEmpty else {
                await worker.disconnect()
                errorMessage = String(localized: .Strings.networkingErrorNoSharedFolders)
                isConnected = false
                currentConnectionID = ""
                folderTree = []
                isLoading = false
                return
            }
            
            // Connection verified! Save server credentials for future use
            await saveValidatedConnection(host: cleanHost, user: user, pass: pass, hostname: hostname)
            if let saved = savedConnections.first(where: { $0.id == "\(user)@\(cleanHost)" }) {
                self.currentLocation = StorageLocation(smb: saved)
            }
            
            self.selectedFolder = nil
            self.activeFolderID = nil
            self.currentFolders = []
            self.pictures = []
            self.folderTree = discoveredShares
            self.isConnected = true
            
            // Auto-restore previously selected folder for this location, or auto-select if only 1 share
            let locID = currentLocation?.id ?? connID
            if let remembered = lastSelectedFolderPerLocation[locID],
               discoveredShares.contains(where: { $0.shareName == remembered.shareName || $0.name == remembered.name }) {
                await selectAndLoadFolder(remembered)
            } else if discoveredShares.count == 1, let singleShare = discoveredShares.first {
                await selectAndLoadFolder(singleShare)
            }
        } catch is CancellationError {
            await worker.disconnect()
            self.errorMessage = nil
            self.isConnected = false
            self.currentConnectionID = ""
            self.folderTree = []
        } catch {
            await worker.disconnect()
            self.errorMessage = String(localized: .Strings.networkingErrorConnectionFailed(error.localizedDescription))
            self.isConnected = false
            self.currentConnectionID = ""
            self.folderTree = []
        }
        
        isLoading = false
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
                self.folderTree = [rootItem]
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
            self.folderTree = refreshedShares
            
            if let current = selectedFolder {
                await selectAndLoadFolder(current)
            }
        } catch {
            self.errorMessage = String(localized: .Strings.networkingErrorRefreshSharesFailed(error.localizedDescription))
        }
    }
    
    // MARK: - Select Folder & Load Both Subfolders + Pictures
    
    /// Selects a folder item and asynchronously enumerates its child subfolders and media files.
    ///
    /// ### Concurrency and Invalidation Strategy
    /// 1. Advances `folderGeneration` and cancels any ongoing `loadFolderTask` to prioritize the new user action.
    /// 2. Clears the existing `pictures` and `currentFolders` collections to cause obsolete UI
    ///    cells to unmount and drop their active thumbnail generation tasks.
    /// 3. Signals the `worker` actor with the new `activeFolderID` to discard queued thumbnail requests.
    /// 4. Checks cooperative task cancellation and `folderGeneration` before committing state.
    ///
    /// - Parameter folder: The folder item to browse.
    public func selectAndLoadFolder(_ folder: MediaItem) async {
        // Record this folder as the last active selection for the current location
        if let locID = currentLocation?.id, !locID.isEmpty {
            lastSelectedFolderPerLocation[locID] = folder
        }

        // 1. Advance generation and cancel any ongoing folder scan task immediately
        folderGeneration &+= 1
        let expectedGeneration = folderGeneration
        loadFolderTask?.cancel()
        loadFolderTask = nil

        // 2. Set newly selected folder and record active folder ID
        selectedFolder = folder
        activeFolderID = folder.id
        isLoading = true
        errorMessage = nil

        // 3. Immediately clear out previous items so thumbnail views unmount
        // and cancel their ongoing thumbnail tasks in SwiftUI
        pictures = []
        currentFolders = []

        // 4. Notify worker actor of active folder change to immediately invalidate pending thumbnails
        await worker.setActiveFolder(id: folder.id)

        // 5. Spawn cancellable task and await its completion
        let targetID = folder.id
        guard !Task.isCancelled,
              self.folderGeneration == expectedGeneration,
              self.activeFolderID == targetID else {
            if self.folderGeneration == expectedGeneration, self.activeFolderID == targetID {
                self.isLoading = false
            }
            return
        }

        let targetShare = folder.shareName
        let targetPath = folder.path
        let targetName = folder.name
        let isLocal = folder.localURL != nil
        let isPhotos = folder.locationID == StorageLocation.photosLocationID

        let task = Task { [weak self, worker, localWorker, photosWorker] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let subfolders: [MediaItem]
                let foundPictures: [MediaItem]

                if isLocal {
                    let (subs, media) = try await localWorker.listContents(at: folder, locationID: folder.connectionID)
                    subfolders = subs
                    foundPictures = media
                } else if isPhotos {
                    let (subs, media) = try await photosWorker.listContents(at: folder)
                    subfolders = subs
                    foundPictures = media
                } else {
                    let (subs, media) = try await worker.scanFolder(shareName: targetShare, at: targetPath)
                    subfolders = subs
                    foundPictures = media
                }

                try Task.checkCancellation()

                guard !Task.isCancelled,
                      self.folderGeneration == expectedGeneration,
                      self.activeFolderID == targetID else {
                    return
                }

                self.currentFolders = subfolders
                self.pictures = foundPictures
                self.folderTree = self.updateTreeNodes(in: self.folderTree, targetID: targetID, children: subfolders)
                self.isLoading = false
                AppLog.smb.info("Folder '\(targetShare, privacy: .private)' path '\(targetPath, privacy: .private)': \(subfolders.count) subfolders, \(foundPictures.count) items")
            } catch is CancellationError {
                // Clean up loading flag only if this folder was not superseded by a newer selection
                if self.folderGeneration == expectedGeneration, self.activeFolderID == targetID {
                    self.isLoading = false
                }
            } catch {
                guard !Task.isCancelled,
                      self.folderGeneration == expectedGeneration,
                      self.activeFolderID == targetID else {
                    return
                }
                self.errorMessage = String(localized: .Strings.networkingErrorLoadFolderFailed(targetName, error.localizedDescription))
                self.isLoading = false
                AppLog.smb.error("Error scanning folder \(targetShare, privacy: .private)/\(targetPath, privacy: .private): \(error.localizedDescription)")
            }
        }

        loadFolderTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if self.folderGeneration == expectedGeneration {
            self.loadFolderTask = nil
        }
    }
    
    /// Lazily populates child subfolders in the sidebar tree without altering the active grid selection.
    ///
    /// - Parameter folder: The folder node being expanded in the sidebar.
    public func loadSubfoldersForTree(at folder: MediaItem) async {
        do {
            let subfolders: [MediaItem]
            if folder.localURL != nil {
                let (subs, _) = try await localWorker.listContents(at: folder, locationID: folder.connectionID)
                subfolders = subs
            } else if folder.locationID == StorageLocation.photosLocationID {
                let (subs, _) = try await photosWorker.listContents(at: folder)
                subfolders = subs
            } else {
                let (subs, _) = try await worker.scanFolder(shareName: folder.shareName, at: folder.path)
                subfolders = subs
            }
            self.folderTree = updateTreeNodes(in: self.folderTree, targetID: folder.id, children: subfolders)
        } catch {
            AppLog.smb.error("Failed to expand tree at \(folder.shareName, privacy: .private)/\(folder.path, privacy: .private): \(error.localizedDescription)")
        }
    }
    
    /// Pure functional recursive tree traversal that injects loaded child nodes into the corresponding parent.
    ///
    /// - Parameters:
    ///   - nodes: The current subtree list.
    ///   - targetID: The identifier of the parent node to receive children.
    ///   - children: The discovered child subfolders.
    /// - Returns: A newly constructed tree reflecting the updated child hierarchy.
    private func updateTreeNodes(in nodes: [MediaItem], targetID: String, children: [MediaItem]) -> [MediaItem] {
        nodes.map { node in
            var updated = node
            if node.id == targetID {
                updated.children = children.isEmpty ? nil : children
            } else if let existingChildren = node.children {
                updated.children = updateTreeNodes(in: existingChildren, targetID: targetID, children: children)
            }
            return updated
        }
    }
    
    // MARK: - Parent Folder Navigation
    
    /// Determines whether a folder represents the top-level root of its storage backend.
    ///
    /// - Parameter item: The media item folder to inspect.
    /// - Returns: `true` if the folder cannot be navigated above; `false` otherwise.
    public func isRootFolder(_ item: MediaItem) -> Bool {
        navigationCoordinator.isRootFolder(item)
    }
    
    /// Recomputes and caches the parent folder of the currently selected folder.
    public func updateParentFolder() {
        parentFolder = navigationCoordinator.resolveParentFolder(for: selectedFolder, in: folderTree)
    }
    
    /// Recursively searches the expanded tree hierarchy to locate the immediate parent of a target node.
    ///
    /// - Parameters:
    ///   - target: The child item whose parent is sought.
    ///   - nodes: The tree nodes to search.
    /// - Returns: The parent `MediaItem` if discovered in the tree, or `nil`.
    public func findParentInTree(for target: MediaItem, in nodes: [MediaItem]) -> MediaItem? {
        navigationCoordinator.findParentInTree(for: target, in: nodes)
    }
    
    /// Synthesizes a parent `MediaItem` using path-based string surgery when tree metadata is unavailable.
    ///
    /// - Parameter item: The child folder item.
    /// - Returns: The derived parent `MediaItem`, or `nil` if already at root.
    public func deriveParentFolder(for item: MediaItem) -> MediaItem? {
        navigationCoordinator.deriveParentFolder(for: item, in: folderTree)
    }
    
    /// Human-readable formatted string indicating total media cache disk usage.
    public var mediaCacheSize: String = "…"
    
    // MARK: - Disconnect
    
    /// Disconnects from the active storage location and resets all navigation and selection state.
    public func disconnect() async {
        folderGeneration &+= 1
        loadFolderTask?.cancel()
        loadFolderTask = nil
        activeFolderID = nil
        currentConnectionID = ""
        currentLocation = nil
        
        isConnected = false
        isLoading = false
        errorMessage = nil
        folderTree = []
        currentFolders = []
        selectedFolder = nil
        pictures = []
        
        await localWorker.deactivateCurrentLocation()
        await worker.setActiveFolder(id: nil)
        await worker.disconnect()
    }
}
