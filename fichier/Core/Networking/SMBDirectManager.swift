//
//  SMBDirectManager.swift
//  fichier
//

import Foundation
import Observation
import UIKit
import AVFoundation
import OSLog

@Observable
@MainActor
public final class SMBDirectManager {
    public var isConnected = false
    public var isLoading = false
    public var errorMessage: String?
    
    // Saved validated server connections
    public var savedConnections: [SavedSMBConnection] = []
    
    // Saved local and iCloud Drive folder locations
    public var savedFolderLocations: [SavedFolderLocation] = []
    
    // Currently active location (SMB or Local/iCloud Folder)
    public var currentLocation: StorageLocation?
    
    // Root tree of shared folders for Sidebar Tree
    public var folderTree: [MediaItem] = []
    
    // Subfolders of the currently selected folder
    public var currentFolders: [MediaItem] = []
    
    // Currently selected folder in the SplitView
    public var selectedFolder: MediaItem?
    
    // Pictures in the currently selected folder
    public var pictures: [MediaItem] = []
    
    // Tracks current active folder to cancel out-of-order thumbnail requests
    public private(set) var activeFolderID: String?
    public private(set) var currentConnectionID: String = ""
    private var loadFolderTask: Task<Void, Never>?
    
    private let worker = SMBClientActor()
    nonisolated var clientActor: SMBClientActor { worker }
    private let localWorker = LocalStorageActor()
    private let photosWorker = PhotoLibraryActor()
    private let videoThumbnailLimiter = VideoThumbnailLimiter()
    private let savedConnectionsKey = "SavedSMBServerConnections_v2"
    private let savedFolderLocationsKey = "SavedFolderLocations_v1"
    
    public init() {
        loadSavedConnections()
        loadSavedFolderLocations()
    }
    
    // MARK: - Saved Connections Persistence
    
    public func loadSavedConnections() {
        guard let data = UserDefaults.standard.data(forKey: savedConnectionsKey),
              let decoded = try? JSONDecoder().decode([SavedSMBConnection].self, from: data) else {
            savedConnections = []
            return
        }
        savedConnections = decoded.sorted { $0.lastConnected > $1.lastConnected }
    }
    
    public func password(for connection: SavedSMBConnection) -> String {
        SMBKeychain.loadPassword(for: connection.id) ?? ""
    }
    
    private func saveValidatedConnection(host: String, user: String, pass: String, hostname: String? = nil) {
        let existingHostname = savedConnections.first(where: { $0.id == "\(user)@\(host)" })?.hostname
        let finalHostname = hostname ?? existingHostname
        
        let newEntry = SavedSMBConnection(
            host: host,
            username: user,
            lastConnected: Date(),
            hostname: finalHostname
        )
        SMBKeychain.savePassword(pass, for: newEntry.id)
        
        var updated = savedConnections.filter { $0.id != newEntry.id }
        updated.insert(newEntry, at: 0)
        savedConnections = updated
        
        if let encoded = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(encoded, forKey: savedConnectionsKey)
        }
    }
    
    public func removeSavedConnection(_ connection: SavedSMBConnection) {
        SMBKeychain.deletePassword(for: connection.id)
        savedConnections.removeAll { $0.id == connection.id }
        if let encoded = try? JSONEncoder().encode(savedConnections) {
            UserDefaults.standard.set(encoded, forKey: savedConnectionsKey)
        }
    }
    
    // MARK: - Saved Folder Locations Persistence (Local & iCloud Drive)
    
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
    
    public func loadSavedFolderLocations() {
        guard let data = UserDefaults.standard.data(forKey: savedFolderLocationsKey),
              let decoded = try? JSONDecoder().decode([SavedFolderLocation].self, from: data) else {
            savedFolderLocations = []
            return
        }
        savedFolderLocations = decoded.sorted { $0.dateAdded > $1.dateAdded }
    }
    
    public func addSavedFolderLocation(_ location: SavedFolderLocation) {
        var updated = savedFolderLocations.filter { $0.id != location.id }
        updated.insert(location, at: 0)
        savedFolderLocations = updated
        if let encoded = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(encoded, forKey: savedFolderLocationsKey)
        }
    }
    
    public func removeSavedFolderLocation(_ location: SavedFolderLocation) {
        savedFolderLocations.removeAll { $0.id == location.id }
        if currentLocation?.folderLocation?.id == location.id {
            Task {
                await disconnect()
            }
        }
        if let encoded = try? JSONEncoder().encode(savedFolderLocations) {
            UserDefaults.standard.set(encoded, forKey: savedFolderLocationsKey)
        }
    }
    
    private func updateBookmarkData(_ bookmarkData: Data, for folderLocation: SavedFolderLocation) {
        if let index = savedFolderLocations.firstIndex(where: { $0.id == folderLocation.id }) {
            let updated = SavedFolderLocation(
                id: folderLocation.id,
                name: folderLocation.name,
                bookmarkData: bookmarkData,
                isICloud: folderLocation.isICloud,
                dateAdded: folderLocation.dateAdded
            )
            savedFolderLocations[index] = updated
            if let encoded = try? JSONEncoder().encode(savedFolderLocations) {
                UserDefaults.standard.set(encoded, forKey: savedFolderLocationsKey)
            }
        }
    }
    
    public func removeLocation(_ location: StorageLocation) {
        switch location.kind {
        case .smb:
            if let smb = location.smbConnection {
                removeSavedConnection(smb)
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
    
    public func selectLocation(_ location: StorageLocation) async {
        switch location.kind {
        case .smb:
            guard let conn = location.smbConnection else { return }
            currentLocation = location
            let pass = password(for: conn)
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
                await selectAndLoadFolder(rootItem)
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
                
                if let firstAlbum = albums.first {
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
            saveValidatedConnection(host: cleanHost, user: user, pass: pass, hostname: hostname)
            if let saved = savedConnections.first(where: { $0.id == "\(user)@\(cleanHost)" }) {
                self.currentLocation = StorageLocation(smb: saved)
            }
            
            self.folderTree = discoveredShares
            self.isConnected = true
            
            // Automatically select and load the first shared folder
            if let firstShare = discoveredShares.first {
                await selectAndLoadFolder(firstShare)
            }
        } catch {
            self.errorMessage = String(localized: .Strings.networkingErrorConnectionFailed(error.localizedDescription))
            self.isConnected = false
        }
        
        isLoading = false
    }
    
    // MARK: - Refresh Shares & Current Folder
    
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
            } else if let first = refreshedShares.first {
                await selectAndLoadFolder(first)
            }
        } catch {
            self.errorMessage = String(localized: .Strings.networkingErrorRefreshSharesFailed(error.localizedDescription))
        }
    }
    
    // MARK: - Select Folder & Load Both Subfolders + Pictures
    
    public func selectAndLoadFolder(_ folder: MediaItem) async {
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
    
    // MARK: - Download Picture / Thumbnail
    
    public func downloadThumbnail(for item: MediaItem, maxDimension: CGFloat = 260) async -> UIImage? {
        if Task.isCancelled { return nil }
        
        // Photos Library asset thumbnail
        if item.phAssetIdentifier != nil {
            let memoryCacheKey = "\(item.id)_thumb_\(Int(maxDimension))" as NSString
            if let cached = await worker.getCachedThumbnail(forKey: memoryCacheKey) {
                return cached
            }
            if let thumb = await photosWorker.fetchThumbnail(for: item, maxDimension: maxDimension) {
                await worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                return thumb
            }
            return nil
        }
        
        // Local or iCloud Drive file thumbnail
        if item.localURL != nil {
            let memoryCacheKey = "\(item.id)_thumb_\(Int(maxDimension))" as NSString
            if let cached = await worker.getCachedThumbnail(forKey: memoryCacheKey) {
                return cached
            }
            if let thumb = await localWorker.fetchThumbnail(for: item, maxDimension: maxDimension) {
                await worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                return thumb
            }
            return nil
        }
        
        let currentActive = activeFolderID
        // Early discard if folder already changed
        if let current = selectedFolder, item.shareName != current.shareName || !item.path.hasPrefix(current.path) {
            return nil
        }
        
        let memoryCacheKey = "\(item.id)_thumb_\(Int(maxDimension))" as NSString
        if let cached = await worker.getCachedThumbnail(forKey: memoryCacheKey) {
            return cached
        }
        
        // Video thumbnail streaming & caching
        if item.isVideo {
            let diskKey = MediaCacheManager.shared.cacheKey(
                for: item.shareName,
                path: "\(item.path)_vidstream_v7",
                dimension: maxDimension,
                connectionID: item.connectionID
            )
            let fallbackKey = !item.connectionID.isEmpty ? MediaCacheManager.shared.cacheKey(
                for: item.shareName,
                path: "\(item.path)_vidstream_v7",
                dimension: maxDimension,
                connectionID: ""
            ) : nil
            if let diskCached = MediaCacheManager.shared.getThumbnail(for: diskKey, fallbackKey: fallbackKey) {
                await worker.cacheThumbnail(diskCached, forKey: memoryCacheKey)
                return diskCached
            }
            
            // 1. If full video was already cached locally, extract frame directly from disk file (defaults to 5.0s)
            if MediaCacheManager.shared.hasCachedVideo(for: item) {
                let localURL = MediaCacheManager.shared.localVideoURL(for: item)
                if let thumb = await MediaCacheManager.shared.generateVideoThumbnail(
                    from: localURL,
                    maxDimension: maxDimension,
                    preferredTime: CMTime(seconds: 5.0, preferredTimescale: 600)
                ) {
                    await worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                    MediaCacheManager.shared.saveThumbnail(thumb, for: diskKey)
                    return thumb
                }
            }
            
            // 2. Stream video frame on demand via AVAssetResourceLoader (reads front header + moov atom only!)
            if let thumb = await streamVideoThumbnail(for: item, maxDimension: maxDimension) {
                await worker.cacheThumbnail(thumb, forKey: memoryCacheKey)
                MediaCacheManager.shared.saveThumbnail(thumb, for: diskKey)
                return thumb
            }
            
            // 3. If streaming failed or was cancelled due to scrolling, do NOT cache a placeholder
            // This allows the cell to retry fetching the actual thumbnail when visible
            return nil
        }
        
        return await worker.fetchThumbnail(for: item, expectedFolderID: currentActive, maxDimension: maxDimension)
    }
    
    /// Streams minimal byte slices on demand using the same progressive loader as the player to extract a keyframe
    private func streamVideoThumbnail(for item: MediaItem, maxDimension: CGFloat) async -> UIImage? {
        if Task.isCancelled { return nil }
        
        return await videoThumbnailLimiter.withPermit {
            if Task.isCancelled { return nil }
            
            var validItem = item
            if validItem.size <= 0 {
                let realSize = await fetchFileSize(for: item)
                if realSize > 0 {
                    validItem = MediaItem(
                        locationID: item.locationID,
                        name: item.name,
                        rootName: item.rootName,
                        path: item.path,
                        isDirectory: item.isDirectory,
                        size: realSize,
                        modifiedDate: item.modifiedDate
                    )
                }
            }
            guard validItem.size > 0 else { return nil }
            
            let uniqueID = UUID().uuidString
            let safeName = validItem.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "video.mp4"
            guard let streamURL = URL(string: "smbstream://localhost/\(uniqueID)/\(safeName)") else {
                return nil
            }
            
            let asset = AVURLAsset(url: streamURL)
            let delegate = SMBResourceLoaderDelegate(worker: worker, item: validItem)
            let queue = DispatchQueue(label: "com.acme.ios.photos.thumbstream.\(uniqueID)", qos: .userInitiated)
            asset.resourceLoader.setDelegate(delegate, queue: queue)
            
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxDimension * 2, height: maxDimension * 2)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 2.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 2.5, preferredTimescale: 600)
            
            return await withTaskCancellationHandler {
                await withTaskGroup(of: UIImage?.self) { group in
                    group.addTask {
                        // 1. Try 5.0s frame first (representative preview)
                        do {
                            let (cgImage, _) = try await generator.image(at: CMTime(seconds: 5.0, preferredTimescale: 600))
                            return UIImage(cgImage: cgImage)
                        } catch {
                            guard !Task.isCancelled else { return nil }
                            // 2. Fallback: try .zero or 0.5s if video is shorter than 5s
                            generator.requestedTimeToleranceBefore = .positiveInfinity
                            generator.requestedTimeToleranceAfter = .positiveInfinity
                            if let (cgImage, _) = try? await generator.image(at: .zero) {
                                return UIImage(cgImage: cgImage)
                            }
                            if let (cgImage, _) = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)) {
                                return UIImage(cgImage: cgImage)
                            }
                            return nil
                        }
                    }
                    
                    group.addTask {
                        try? await Task.sleep(for: .seconds(12.0))
                        return nil
                    }
                    
                    let first = await group.next() ?? nil
                    group.cancelAll()
                    generator.cancelAllCGImageGeneration()
                    delegate.cancelAll()
                    return first
                }
            } onCancel: {
                generator.cancelAllCGImageGeneration()
                delegate.cancelAll()
            }
        }
    }
    
    public func downloadImage(for item: MediaItem) async -> UIImage? {
        if Task.isCancelled || item.isVideo { return nil }
        if item.phAssetIdentifier != nil {
            return await photosWorker.fetchImage(for: item)
        }
        if item.localURL != nil {
            return await localWorker.fetchImage(for: item)
        }
        return await worker.fetchFullImage(for: item)
    }
    
    public func fetchFileSize(for item: MediaItem) async -> Int64 {
        if item.phAssetIdentifier != nil {
            return await photosWorker.fetchFileSize(for: item)
        }
        if item.localURL != nil {
            return await localWorker.fetchFileSize(for: item)
        }
        return await worker.fetchFileSize(for: item)
    }
    
    public func fetchMetadata(for item: MediaItem) async -> PictureEXIFData? {
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
    
    nonisolated public func fetchMediaRange(for item: MediaItem, offset: Int64, length: Int) async throws -> Data {
        try await worker.fetchMediaRange(for: item, offset: offset, length: length)
    }
    
    public func fetchVideoURL(for item: MediaItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        if item.phAssetIdentifier != nil {
            return try await photosWorker.fetchVideoURL(for: item)
        }
        if let localURL = item.localURL {
            return localURL
        }
        return try await worker.fetchVideoURL(for: item, progress: progress)
    }
    
    public var mediaCacheSize: String {
        MediaCacheManager.shared.formattedCacheSize()
    }
    
    public func clearMediaCache() {
        MediaCacheManager.shared.clearAllCache()
        Task {
            await worker.clearMemoryCache()
        }
    }
    
    // MARK: - Disconnect
    
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
