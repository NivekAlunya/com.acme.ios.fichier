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

/// Centralized state manager and coordinator for all media storage backends in the application.
///
/// `StorageLocationManager` is an `@Observable` model object isolated to the `@MainActor`. It coordinates
/// browsing, caching, and streaming across three distinct storage backends:
/// 1. **SMB Network Shares** — Managed via `SMBClientActor` and authenticated via `SMBKeychain`.
/// 2. **Local and iCloud Drive Folders** — Managed via `LocalStorageActor` using security-scoped bookmarks.
/// 3. **Apple Photos Library** — Managed via `PhotoLibraryActor` using PhotoKit.
///
/// ### Key Responsibilities
/// - Maintains active connections and persisted credentials for servers and local folders.
/// - Drives navigation through hierarchical folder trees and tracks selected media collections.
/// - Coordinates two-tier in-memory and persistent disk caching for thumbnails and full-resolution media.
/// - Dispatches video thumbnail generation through a bounded concurrency limiter (`VideoThumbnailLimiter`)
///   and custom resource loaders (`SMBResourceLoaderDelegate`).
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
    public private(set) var thumbnailVersions: [String: Int] = [:]
    
    /// In-flight asynchronous folder scanning task, cancelled when switching folders rapidly.
    private var loadFolderTask: Task<Void, Never>?
    
    /// In-memory memory map preserving the last viewed folder per location ID for seamless split-view restoration.
    private var lastSelectedFolderPerLocation: [String: MediaItem] = [:]
    
    /// Background actor managing SMB connections, directory scanning, and streaming.
    private let worker = SMBClientActor()
    
    /// Nonisolated accessor exposing the worker actor for background streaming operations.
    nonisolated var clientActor: SMBClientActor { worker }
    
    /// Background actor managing local sandbox and security-scoped file system access.
    private let localWorker = LocalStorageActor()
    
    /// Background actor managing PhotoKit queries and PHAsset fetching.
    private let photosWorker = PhotoLibraryActor()
    
    /// Concurrency limiter preventing socket saturation during parallel video keyframe extraction.
    private let videoThumbnailLimiter = VideoThumbnailLimiter()
    
    #if !os(tvOS)
    /// Concurrency limiter preventing socket saturation during parallel PDF document thumbnail extraction.
    private let pdfThumbnailLimiter = PDFThumbnailLimiter()
    #endif
    
    /// Persistence store handling SMB credentials and sandboxed folder bookmarks.
    private let persistenceStore = StorageLocationPersistenceStore()
    
    /// Navigation coordinator handling root boundary checks and tree hierarchy derivation.
    private let navigationCoordinator = FolderNavigationCoordinator()
    
    /// Initializes the manager, restoring saved connections and registering lifecycle observers.
    public init() {
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
        
        let credential = URLCredential(user: user, password: pass, persistence: .forSession)
        
        guard let url = URL(string: "smb://\(cleanHost)") else {
            errorMessage = String(localized: .Strings.networkingErrorInvalidHostUrl)
            isLoading = false
            return
        }
        
        let connID = user.isEmpty ? cleanHost : "\(user)@\(cleanHost)"
        self.currentConnectionID = connID
        
        do {
            let discoveredShares = try await worker.connectAndListShares(url: url, credential: credential, connectionID: connID)
            guard !discoveredShares.isEmpty else {
                errorMessage = String(localized: .Strings.networkingErrorNoSharedFolders)
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
        } catch {
            self.errorMessage = String(localized: .Strings.networkingErrorConnectionFailed(error.localizedDescription))
            self.isConnected = false
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
    /// 1. Immediately cancels any ongoing `loadFolderTask` to prioritize the new user action.
    /// 2. Clears the existing `pictures` and `currentFolders` collections to cause obsolete UI
    ///    cells to unmount and drop their active thumbnail generation tasks.
    /// 3. Signals the `worker` actor with the new `activeFolderID` to discard queued thumbnail requests.
    /// 4. Checks cooperative task cancellation (`Task.checkCancellation()`) before committing state.
    ///
    /// - Parameter folder: The folder item to browse.
    public func selectAndLoadFolder(_ folder: MediaItem) async {
        // Record this folder as the last active selection for the current location
        if let locID = currentLocation?.id, !locID.isEmpty {
            lastSelectedFolderPerLocation[locID] = folder
        }
        
        // 1. Cancel previous folder scan task immediately
        loadFolderTask?.cancel()
        
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
                
                guard !Task.isCancelled, self.activeFolderID == targetID else { return }
                self.currentFolders = subfolders
                self.pictures = foundPictures
                self.folderTree = self.updateTreeNodes(in: self.folderTree, targetID: targetID, children: subfolders)
                self.isLoading = false
                AppLog.smb.info("Folder '\(targetShare, privacy: .private)' path '\(targetPath, privacy: .private)': \(subfolders.count) subfolders, \(foundPictures.count) items")
            } catch is CancellationError {
                // Superseded by another folder click; silently exit
            } catch {
                guard !Task.isCancelled, self.activeFolderID == targetID else { return }
                self.errorMessage = String(localized: .Strings.networkingErrorLoadFolderFailed(targetName, error.localizedDescription))
                self.isLoading = false
                AppLog.smb.error("Error scanning folder \(targetShare, privacy: .private)/\(targetPath, privacy: .private): \(error.localizedDescription)")
            }
        }
        
        loadFolderTask = task
        await task.value
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
    
    // MARK: - Download Picture / Thumbnail
    
    /// Downloads or retrieves a cached thumbnail image for a given media item.
    ///
    /// ### Multi-Tier Thumbnail Pipeline
    /// 1. **Tier 1 (RAM)**: Checks `SMBClientActor`'s in-memory `NSCache` for immediate rendering.
    /// 2. **Backend Delegation**:
    ///    - Photos Library: Delegated to `PhotoLibraryActor` (`PHCachingImageManager`).
    ///    - Local Files: Checks persistent disk cache (`MediaCacheManager`), then decodes with downsampling.
    ///    - SMB Videos: Checks disk cache, then extracts a keyframe over the network via `streamVideoThumbnail`.
    ///    - SMB Images: Checks disk cache, debounces by 40ms, and queries `SMBClientActor`.
    /// 3. **Tier 2 (Disk Storage)**: Successfully decoded images are written back to `MediaCacheManager`.
    ///
    /// - Parameters:
    ///   - item: The target media item.
    ///   - maxDimension: Maximum pixel bounding dimension for downsampling.
    /// - Returns: A decoded, downsampled `UIImage`, or `nil` if loading failed or was cancelled.
    public func downloadThumbnail(for item: MediaItem, maxDimension: CGFloat = 260) async -> UIImage? {
        if Task.isCancelled { return nil }
        
        let memoryCacheKey = "\(item.id)_thumb" as NSString
        let legacyMemoryKey = "\(item.id)_thumb_\(Int(maxDimension))" as NSString
        if let cached = worker.getCachedThumbnail(forKey: memoryCacheKey) ?? worker.getCachedThumbnail(forKey: legacyMemoryKey) {
            return cached
        }
        
        // Photos Library asset thumbnail
        if item.phAssetIdentifier != nil {
            if let thumb = await photosWorker.fetchThumbnail(for: item, maxDimension: maxDimension) {
                worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                return thumb
            }
            return nil
        }
        
        // Local or iCloud Drive file thumbnail
        if item.localURL != nil {
            // Check persistent on-disk thumbnail cache (Tier 2) to eliminate re-decoding local video/image files
            let subPath = item.isVideo ? "\(item.path)_vidstream_v7" : item.path
            let (diskKey, fallbackKey, legacyKey) = MediaCacheManager.shared.thumbnailKeys(
                for: item.shareName,
                path: subPath,
                dimension: maxDimension,
                connectionID: item.connectionID
            )
            if let diskCached = await MediaCacheManager.shared.getThumbnailAsync(for: diskKey, fallbackKey: fallbackKey, legacyKey: legacyKey) {
                worker.cacheThumbnail(diskCached, forKey: memoryCacheKey)
                return diskCached
            }
            
            if let thumb = await localWorker.fetchThumbnail(for: item, maxDimension: maxDimension) {
                worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                return thumb
            }
            return nil
        }
        
        let currentActive = activeFolderID
        // Early discard if folder already changed
        if let current = selectedFolder, item.shareName != current.shareName || !item.path.hasPrefix(current.path) {
            return nil
        }
        
        // Video thumbnail streaming & caching
        if item.isVideo {
            let (diskKey, fallbackKey, legacyKey) = MediaCacheManager.shared.thumbnailKeys(
                for: item.shareName,
                path: "\(item.path)_vidstream_v7",
                dimension: maxDimension,
                connectionID: item.connectionID
            )
            if let diskCached = await MediaCacheManager.shared.getThumbnailAsync(for: diskKey, fallbackKey: fallbackKey, legacyKey: legacyKey) {
                worker.cacheThumbnail(diskCached, forKey: memoryCacheKey)
                return diskCached
            }
            
            guard !Task.isCancelled else { return nil }
            
            // 1. If full video was already cached locally, extract frame directly from disk file (defaults to 12.0s with 0.0s fallback)
            if MediaCacheManager.shared.hasCachedVideo(for: item) {
                let localURL = MediaCacheManager.shared.localVideoURL(for: item)
                if let thumb = await MediaCacheManager.shared.generateVideoThumbnail(
                    from: localURL,
                    maxDimension: MediaCacheManager.standardThumbnailDimension
                ) {
                    worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                    MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                    return thumb
                }
            }
            
            // 2. Stream video frame on demand via AVAssetResourceLoader (reads front header + moov atom only!)
            // Debounce briefly so cells flying past during fast scroll are cancelled before hitting SMB
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return nil }
            
            if let thumb = await streamVideoThumbnail(for: item, expectedFolderID: currentActive, maxDimension: MediaCacheManager.standardThumbnailDimension) {
                worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                return thumb
            }
            
            // 3. If streaming failed or was cancelled due to scrolling, do NOT cache a placeholder
            // This allows the cell to retry fetching the actual thumbnail when visible
            return nil
        }
        
        // PDF document thumbnail streaming, fast-path prefix caching, and placeholder generation
        if item.isPDF {
            return await fetchPDFThumbnail(for: item, expectedFolderID: currentActive, maxDimension: MediaCacheManager.standardThumbnailDimension)
        }
        
        // Check persistent disk cache for SMB photos off the MainActor before queuing on SMBClientActor
        let (photoDiskKey, photoFallbackKey, photoLegacyKey) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: maxDimension,
            connectionID: item.connectionID
        )
        if let diskCached = await MediaCacheManager.shared.getThumbnailAsync(for: photoDiskKey, fallbackKey: photoFallbackKey, legacyKey: photoLegacyKey) {
            worker.cacheThumbnail(diskCached, forKey: memoryCacheKey)
            return diskCached
        }
        
        // Debounce briefly (40ms for photos) to prevent network thrashing during fast scrolls
        try? await Task.sleep(for: .milliseconds(40))
        guard !Task.isCancelled else { return nil }
        
        let thumb = await worker.fetchThumbnail(for: item, expectedFolderID: currentActive, maxDimension: maxDimension)
        if let thumb {
            worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
        }
        return thumb
    }
    
    // MARK: - Streaming Helpers
    
    /// Constructs a virtual custom scheme URL (`smbstream://`) intercepted by AVPlayer and AVAssetResourceLoader.
    ///
    /// - Parameters:
    ///   - itemName: File name of the media asset.
    ///   - uniqueID: Session UUID distinguishing resource loader instances.
    /// - Returns: A tuple with the synthetic streaming URL and its unique session identifier.
    nonisolated public static func makeStreamURL(for itemName: String, uniqueID: String = UUID().uuidString) -> (url: URL, uniqueID: String)? {
        let safeName = itemName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "video.mp4"
        guard let url = URL(string: "smbstream://localhost/\(uniqueID)/\(safeName)") else { return nil }
        return (url, uniqueID)
    }
    
    /// Ensures a media item has a positive byte size populated, querying file attributes if missing.
    ///
    /// - Parameter item: The media item to validate.
    /// - Returns: The verified `MediaItem` with positive size metadata.
    public func resolveValidItem(for item: MediaItem) async -> MediaItem {
        guard item.size <= 0 else { return item }
        let realSize = await fetchFileSize(for: item)
        return realSize > 0 ? item.withSize(realSize) : item
    }

    /// Progressive video keyframe extractor over SMB using AVAssetResourceLoader.
    ///
    /// ### Algorithmic Details & Concurrency Control
    /// 1. Uses `videoThumbnailLimiter.withPermit` to cap simultaneous thumbnail extraction tasks (default max 2),
    ///    preventing socket congestion on the SMB server.
    /// 2. Configures `SMBResourceLoaderDelegate` with a 256 KB chunk size for efficient range-request header parsing.
    /// 3. Employs `AVAssetImageGenerator` with tight tolerances targeting a standardized 12.0s timestamp,
    ///    with fallbacks to `.zero` and 1.0s if the video is very short.
    /// 4. Races the extraction against a 12-second timeout inside a structured `TaskGroup`, immediately
    ///    cancelling underlying network requests and CGImage generation upon timeout or external cancellation.
    ///
    /// - Parameters:
    ///   - item: Video media item.
    ///   - expectedFolderID: Active folder identifier to avoid completing obsolete requests.
    ///   - maxDimension: Maximum bounding dimension for the thumbnail.
    /// - Returns: An extracted keyframe image, or `nil`.
    private func streamVideoThumbnail(for item: MediaItem, expectedFolderID: String?, maxDimension: CGFloat) async -> UIImage? {
        if Task.isCancelled { return nil }
        
        return try? await videoThumbnailLimiter.withPermit {
            guard !Task.isCancelled else { return nil }
            if let expectedFolderID, await self.activeFolderID != expectedFolderID {
                return nil
            }
            let memoryCacheKey = "\(item.id)_thumb" as NSString
            let legacyMemoryKey = "\(item.id)_thumb_\(Int(maxDimension))" as NSString
            if let cached = self.worker.getCachedThumbnail(forKey: memoryCacheKey) ?? self.worker.getCachedThumbnail(forKey: legacyMemoryKey) {
                return cached
            }
            
            let validItem = await resolveValidItem(for: item)
            guard validItem.size > 0 else {
                return nil
            }
            
            if SupportedMediaTypes.isExtendedVideo(extension: (validItem.name as NSString).pathExtension) {
                return await streamExtendedVideoThumbnail(for: validItem, maxDimension: maxDimension)
            }
            
            guard let (streamURL, uniqueID) = Self.makeStreamURL(for: validItem.name) else {
                return nil
            }
            
            let asset = AVURLAsset(url: streamURL)
            // Use 256 KB chunk size for thumbnail probing to avoid congesting the SMB socket during concurrent video playback
            let delegate = SMBResourceLoaderDelegate(worker: worker, item: validItem, chunkSize: 256 * 1024)
            // swiftlint:disable:next no_legacy_dispatch_queue
            let queue = DispatchQueue(label: "com.acme.ios.photos.thumbstream.\(uniqueID)", qos: .userInitiated)
            asset.resourceLoader.setDelegate(delegate, queue: queue)
            
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let standardDim = MediaCacheManager.standardThumbnailDimension
            generator.maximumSize = CGSize(width: standardDim, height: standardDim)
            generator.requestedTimeToleranceBefore = MediaCacheManager.defaultVideoThumbnailTolerance
            generator.requestedTimeToleranceAfter = MediaCacheManager.defaultVideoThumbnailTolerance
            
            return await withTaskCancellationHandler {
                await withTaskGroup(of: UIImage?.self) { group in
                    group.addTask {
                        // 1. Try representative frame first using standardized thumbnail timestamp
                        do {
                            let (cgImage, _) = try await generator.image(at: MediaCacheManager.defaultVideoThumbnailTime)
                            return UIImage(cgImage: cgImage)
                        } catch {
                            guard !Task.isCancelled else { return nil }
                            // 2. Fallback: try .zero or standardized fallback timestamp if video is shorter
                            generator.requestedTimeToleranceBefore = .positiveInfinity
                            generator.requestedTimeToleranceAfter = .positiveInfinity
                            if !Task.isCancelled, let (cgImage, _) = try? await generator.image(at: .zero) {
                                return UIImage(cgImage: cgImage)
                            }
                            if !Task.isCancelled, let (cgImage, _) = try? await generator.image(at: MediaCacheManager.fallbackVideoThumbnailTime) {
                                return UIImage(cgImage: cgImage)
                            }
                            return nil
                        }
                    }
                    
                    group.addTask {
                        try? await Task.sleep(for: .seconds(12.0))
                        return nil
                    }
                    
                    let first = (await group.next()).flatMap { $0 }
                    group.cancelAll()
                    generator.cancelAllCGImageGeneration()
                    delegate.cancelAll()
                    asset.resourceLoader.setDelegate(nil, queue: nil)
                    return first
                }
            } onCancel: {
                generator.cancelAllCGImageGeneration()
                delegate.cancelAll()
                asset.resourceLoader.setDelegate(nil, queue: nil)
            }
        }
    }
    
    /// Streams an extended video keyframe (MKV, AVI, WebM, etc.) on demand over loopback HTTP via VLCKit.
    private func streamExtendedVideoThumbnail(
        for item: MediaItem,
        maxDimension: CGFloat
    ) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let server = SMBStreamingServerActor(worker: self.worker, item: item)
        do {
            let streamURL = try await server.start()
            
            let thumb = await VLCMediaThumbnailerActor.shared.generateThumbnail(
                from: streamURL,
                maxDimension: maxDimension,
                snapshotPosition: 0.05
            )
            
            let result: UIImage?
            if let thumb {
                result = thumb
            } else {
                result = await VLCMediaThumbnailerActor.shared.generateThumbnail(
                    from: streamURL,
                    maxDimension: maxDimension,
                    snapshotPosition: 0.0
                )
            }
            
            await server.stop()
            return result
        } catch {
            await server.stop()
            return nil
        }
    }
    
    // MARK: - PDF Document Thumbnail Streaming & Placeholders
    
    /// Progressive PDF document thumbnail generator with fast-path prefix reading and stylized placeholder fallbacks.
    ///
    /// ### Three-Tier Thumbnailing Strategy:
    /// 1. **Cache / Local Ingestion**: Checks RAM, persistent disk thumbnails, or local document cache.
    /// 2. **Fast-Path Prefix Read**: Reads the initial 1 MB prefix over SMB. For linearized (web-optimized) PDFs,
    ///    Page 1 is rendered and cached in ~200ms without transferring the remaining document.
    /// 3. **Bounded Ingestion or Stylized Cover**:
    ///    - If the document is $\le 12 \text{ MB}$, downloads via `PDFThumbnailLimiter` (max 1 concurrent operation)
    ///      with a strict 8-second timeout to prevent socket starvation.
    ///    - If the document exceeds $12 \text{ MB}$, or if download fails/times out, immediately generates an
    ///      elegant stylized vector PDF cover card with title and file size.
    ///
    /// - Parameters:
    ///   - item: The target PDF `MediaItem`.
    ///   - expectedFolderID: Active directory token to verify folder consistency.
    ///   - maxDimension: Maximum thumbnail bounding dimension.
    /// - Returns: A rendered cover `UIImage`, or `nil` if cancelled.
    #if !os(tvOS)
    private func fetchPDFThumbnail(for item: MediaItem, expectedFolderID: String?, maxDimension: CGFloat) async -> UIImage? {
        if Task.isCancelled { return nil }
        
        let memoryCacheKey = "\(item.id)_thumb" as NSString
        let (diskKey, fallbackKey, legacyKey) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: maxDimension,
            connectionID: item.connectionID
        )
        
        // 1. Check persistent on-disk thumbnail cache
        if let diskCached = await MediaCacheManager.shared.getThumbnailAsync(for: diskKey, fallbackKey: fallbackKey, legacyKey: legacyKey) {
            worker.cacheThumbnail(diskCached, forKey: memoryCacheKey)
            return diskCached
        }
        
        // 2. Check if complete document is already cached locally (e.g. previously opened in PDFDetailView)
        if MediaCacheManager.shared.hasCachedDocument(for: item) {
            let localURL = MediaCacheManager.shared.localDocumentURL(for: item)
            if let thumb = MediaCacheManager.shared.generatePDFThumbnail(from: localURL, maxDimension: maxDimension) {
                worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                return thumb
            }
        }
        
        // 3. Debounce briefly (100ms) to cancel fast-scrolling cells before touching SMB
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return nil }
        if let expectedFolderID, self.activeFolderID != expectedFolderID {
            return nil
        }
        
        // 4. Fast-Path Prefix Read (Linearized / Web-Optimized PDFs)
        if let fastThumb = await worker.fetchPDFPrefixThumbnail(for: item, maxDimension: maxDimension) {
            worker.cacheThumbnail(fastThumb, forKey: memoryCacheKey)
            MediaCacheManager.shared.saveThumbnailAsync(fastThumb, for: diskKey)
            return fastThumb
        }
        guard !Task.isCancelled else { return nil }
        
        // 5. Size Ceiling & Concurrency Limiting:
        // Only attempt full download during grid browsing for documents <= 12 MB.
        let maxThumbnailDownloadBytes: Int64 = 12 * 1024 * 1024
        if item.size > 0 && item.size <= maxThumbnailDownloadBytes {
            let thumb = try? await pdfThumbnailLimiter.withPermit { () -> UIImage? in
                guard !Task.isCancelled else { return nil }
                if let expectedFolderID, await self.activeFolderID != expectedFolderID {
                    return nil
                }
                
                // Re-check disk cache in case a previous task finished it while waiting
                if let diskCached = await MediaCacheManager.shared.getThumbnailAsync(for: diskKey, fallbackKey: fallbackKey, legacyKey: legacyKey) {
                    return diskCached
                }
                
                do {
                    // Race download against an 8-second timeout using structured concurrency
                    return try await withThrowingTaskGroup(of: UIImage?.self) { group in
                        group.addTask {
                            let localURL = try await self.worker.fetchDocumentURL(for: item)
                            return MediaCacheManager.shared.generatePDFThumbnail(from: localURL, maxDimension: maxDimension)
                        }
                        group.addTask {
                            try await Task.sleep(for: .seconds(8))
                            return nil
                        }
                        let result = (try await group.next()).flatMap { $0 }
                        group.cancelAll()
                        return result
                    }
                } catch {
                    return nil
                }
            }
            if let thumb {
                worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
                return thumb
            }
        }
        
        // 6. Documents > 12 MB or without a pre-computed thumbnail return nil.
        // MediaThumbnailView will render a zero-allocation lightweight SwiftUI vector placeholder.
        return nil
    }
    
    // MARK: - On-the-Fly Thumbnail Upgrades
    
    /// Upgrades or creates the master thumbnail for a PDF document currently opened in the reader.
    ///
    /// Extracted directly from Page 1 of the parsed in-memory `PDFDocument`, saving network I/O
    /// and disk parsing overhead. Persists the rendered thumbnail to both RAM and disk caches,
    /// and notifies active gallery cells to update immediately.
    ///
    /// - Parameters:
    ///   - item: The target document `MediaItem`.
    ///   - document: The parsed `PDFDocument` currently displayed in the reader.
    public func upgradePDFThumbnail(for item: MediaItem, from document: PDFDocument) async {
        let maxDimension = MediaCacheManager.standardThumbnailDimension
        let (diskKey, _, _) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: maxDimension,
            connectionID: item.connectionID
        )
        let memoryCacheKey = "\(item.id)_thumb" as NSString
        
        // Render first page directly from in-memory document
        guard let thumb = MediaCacheManager.shared.generatePDFThumbnail(from: document, maxDimension: maxDimension) else {
            return
        }
        
        // Persist to disk and RAM
        MediaCacheManager.shared.saveThumbnailAsync(thumb, for: diskKey)
        worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
        
        // Trigger SwiftUI observation update for this item
        thumbnailVersions[item.id, default: 0] += 1
    }
    #else
    private func fetchPDFThumbnail(for item: MediaItem, expectedFolderID: String?, maxDimension: CGFloat) async -> UIImage? {
        nil
    }
    #endif
    
    /// Downloads the full-resolution image for a media item from the active backend.
    ///
    /// - Parameter item: The media item to download.
    /// - Returns: The full-resolution `UIImage`, or `nil` if cancelled or failed.
    nonisolated public func downloadImage(for item: MediaItem) async -> UIImage? {
        if Task.isCancelled || item.isVideo { return nil }
        if item.phAssetIdentifier != nil {
            return await photosWorker.fetchImage(for: item)
        }
        if item.localURL != nil {
            return await localWorker.fetchImage(for: item)
        }
        return await worker.fetchFullImage(for: item)
    }
    
    /// Queries the byte size of a media item from its respective storage backend.
    ///
    /// - Parameter item: The media item to inspect.
    /// - Returns: Size in bytes, or `0` if undetermined.
    nonisolated public func fetchFileSize(for item: MediaItem) async -> Int64 {
        if item.phAssetIdentifier != nil {
            return await photosWorker.fetchFileSize(for: item)
        }
        if item.localURL != nil {
            return await localWorker.fetchFileSize(for: item)
        }
        return await worker.fetchFileSize(for: item)
    }
    
    /// Fetches parsed EXIF and camera metadata for an image without decoding pixel buffers.
    ///
    /// - Parameter item: The media item to inspect.
    /// - Returns: Parsed `PictureEXIFData`, or `nil` if unavailable.
    nonisolated public func fetchMetadata(for item: MediaItem) async -> PictureEXIFData? {
        if Task.isCancelled { return nil }
        if item.phAssetIdentifier != nil {
            return await photosWorker.fetchMetadata(for: item)
        }
        if item.localURL != nil {
            return await localWorker.fetchMetadata(for: item)
        }
        return await worker.fetchMetadata(for: item)
    }
    
    // MARK: - Video Support & Disk Cache (Tier 3)
    
    /// Fetches a specific byte range of a media file over SMB.
    ///
    /// - Parameters:
    ///   - item: The media item being streamed.
    ///   - offset: Starting byte position.
    ///   - length: Requested number of bytes.
    /// - Returns: The retrieved byte chunk.
    nonisolated public func fetchMediaRange(for item: MediaItem, offset: Int64, length: Int) async throws -> Data {
        try await worker.fetchMediaRange(for: item, offset: offset, length: length)
    }
    
    /// Resolves or downloads the playable local or sandbox file URL for a video asset.
    ///
    /// - Parameters:
    ///   - item: Target video media item.
    ///   - progress: Optional progress reporting callback (`Sendable`).
    /// - Returns: Local file `URL` ready for AVPlayer playback.
    public func fetchVideoURL(for item: MediaItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        if item.phAssetIdentifier != nil {
            return try await photosWorker.fetchVideoURL(for: item)
        }
        if let localURL = item.localURL {
            return localURL
        }
        return try await worker.fetchVideoURL(for: item, progress: progress)
    }
    
    /// Resolves or downloads the local file URL for a PDF document asset.
    ///
    /// - Parameters:
    ///   - item: Target document media item.
    ///   - progress: Optional progress reporting callback (`Sendable`).
    /// - Returns: Local file `URL` ready for PDFKit rendering.
    public func fetchDocumentURL(for item: MediaItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        if let localURL = item.localURL {
            return localURL
        }
        return try await worker.fetchDocumentURL(for: item, progress: progress)
    }
    
    /// Human-readable formatted string indicating total media cache disk usage.
    public var mediaCacheSize: String = "…"
    
    /// Queries `MediaCacheManager` and updates `mediaCacheSize` on the `@MainActor`.
    public func refreshMediaCacheSize() async {
        mediaCacheSize = await MediaCacheManager.shared.formattedCacheSize()
    }
    
    /// Purges all cached thumbnails and downloads from both RAM and disk caches.
    public func clearMediaCache() {
        Task {
            await MediaCacheManager.shared.clearAllCacheAsync()
            await worker.clearMemoryCache()
            await refreshMediaCacheSize()
        }
    }
    
    /// Clears both memory and persistent disk thumbnail caches for all items in the currently loaded folder.
    public func invalidateCurrentFolderThumbnails() async {
        let items = pictures
        guard !items.isEmpty else { return }
        
        await MediaCacheManager.shared.invalidateThumbnailCache(for: items)
        
        let ids = items.map(\.id)
        await worker.removeThumbnailsFromMemory(for: ids)
        for id in ids {
            thumbnailVersions[id, default: 0] += 1
        }
        
        await refreshMediaCacheSize()
    }
    
    // MARK: - Disconnect
    
    /// Disconnects from the active storage location and resets all navigation and selection state.
    public func disconnect() async {
        loadFolderTask?.cancel()
        loadFolderTask = nil
        activeFolderID = nil
        currentConnectionID = ""
        currentLocation = nil
        
        isConnected = false
        isLoading = false
        folderTree = []
        currentFolders = []
        selectedFolder = nil
        pictures = []
        
        await localWorker.deactivateCurrentLocation()
        await worker.setActiveFolder(id: nil)
        await worker.disconnect()
    }
}
