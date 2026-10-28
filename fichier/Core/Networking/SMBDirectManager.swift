//
//  SMBDirectManager.swift
//  fichier
//

import Foundation
import Observation
import UIKit
import AVFoundation

@Observable
@MainActor
public final class SMBDirectManager {
    public var isConnected = false
    public var isLoading = false
    public var errorMessage: String?
    
    // Saved validated server connections
    public var savedConnections: [SavedSMBConnection] = []
    
    // Root tree of shared folders for Sidebar Tree
    public var folderTree: [SMBItem] = []
    
    // Subfolders of the currently selected folder
    public var currentFolders: [SMBItem] = []
    
    // Currently selected folder in the SplitView
    public var selectedFolder: SMBItem?
    
    // Pictures in the currently selected folder
    public var pictures: [SMBItem] = []
    
    // Tracks current active folder to cancel out-of-order thumbnail requests
    public private(set) var activeFolderID: String?
    private var loadFolderTask: Task<Void, Never>?
    
    private let worker = SMBClientActor()
    private let videoThumbnailLimiter = VideoThumbnailLimiter()
    private let savedConnectionsKey = "SavedSMBServerConnections_v2"
    
    public init() {
        loadSavedConnections()
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
    
    private func saveValidatedConnection(host: String, user: String, pass: String) {
        let newEntry = SavedSMBConnection(
            host: host,
            username: user,
            lastConnected: Date()
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
    
    // MARK: - Connect to Mac mini & List All Shares Automatically
    
    public func connect(host: String, user: String, pass: String) async {
        isLoading = true
        errorMessage = nil
        
        let cleanHost = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "smb://", with: "")
            .components(separatedBy: "%").first ?? host
        
        if cleanHost.contains(":") && !cleanHost.hasPrefix("[") {
            errorMessage = "Please select or enter an IPv4 address (e.g. 192.168.1.x)."
            isLoading = false
            return
        }
        
        let credential = URLCredential(user: user, password: pass, persistence: .forSession)
        
        guard let url = URL(string: "smb://\(cleanHost)") else {
            errorMessage = "Invalid IPv4 host URL"
            isLoading = false
            return
        }
        
        do {
            let discoveredShares = try await worker.connectAndListShares(url: url, credential: credential)
            guard !discoveredShares.isEmpty else {
                errorMessage = "Connected to server, but no shared folders were found."
                isLoading = false
                return
            }
            
            // Connection verified! Save server credentials for future use
            saveValidatedConnection(host: cleanHost, user: user, pass: pass)
            
            self.folderTree = discoveredShares
            self.isConnected = true
            
            // Automatically select and load the first shared folder
            if let firstShare = discoveredShares.first {
                await selectAndLoadFolder(firstShare)
            }
        } catch {
            self.errorMessage = "Connection failed: \(error.localizedDescription)"
            self.isConnected = false
        }
        
        isLoading = false
    }
    
    // MARK: - Refresh Shares & Current Folder
    
    public func refreshSharesAndFolders() async {
        errorMessage = nil
        do {
            let refreshedShares = try await worker.refreshShares()
            self.folderTree = refreshedShares
            
            if let current = selectedFolder {
                await selectAndLoadFolder(current)
            } else if let first = refreshedShares.first {
                await selectAndLoadFolder(first)
            }
        } catch {
            self.errorMessage = "Failed to refresh shares: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Select Folder & Load Both Subfolders + Pictures
    
    public func selectAndLoadFolder(_ folder: SMBItem) async {
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
        
        let task = Task { [weak self, worker] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let (subfolders, foundPictures) = try await worker.scanFolder(shareName: targetShare, at: targetPath)
                try Task.checkCancellation()
                
                await MainActor.run {
                    guard !Task.isCancelled, self.activeFolderID == targetID else { return }
                    self.currentFolders = subfolders
                    self.pictures = foundPictures
                    self.folderTree = self.updateTreeNodes(in: self.folderTree, targetID: targetID, children: subfolders)
                    self.isLoading = false
                    print("✅ [SMB] Share '\(targetShare)' path '\(targetPath)': \(subfolders.count) subfolders, \(foundPictures.count) pictures")
                }
            } catch is CancellationError {
                // Superseded by another folder click; silently exit
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled, self.activeFolderID == targetID else { return }
                    self.errorMessage = "Failed to load folder '\(targetName)': \(error.localizedDescription)"
                    self.isLoading = false
                    print("❌ [SMB] Error scanning folder \(targetShare)/\(targetPath): \(error)")
                }
            }
        }
        
        loadFolderTask = task
        await task.value
    }
    
    public func loadSubfoldersForTree(at folder: SMBItem) async {
        do {
            let (subfolders, _) = try await worker.scanFolder(shareName: folder.shareName, at: folder.path)
            self.folderTree = updateTreeNodes(in: self.folderTree, targetID: folder.id, children: subfolders)
        } catch {
            print("❌ [SMB] Failed to expand tree at \(folder.shareName)/\(folder.path): \(error)")
        }
    }
    
    private func updateTreeNodes(in nodes: [SMBItem], targetID: String, children: [SMBItem]) -> [SMBItem] {
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
    
    public func downloadThumbnail(for item: SMBItem, maxDimension: CGFloat = 260) async -> UIImage? {
        if Task.isCancelled { return nil }
        let currentActive = activeFolderID
        // Early discard if folder already changed
        if let current = selectedFolder, item.shareName != current.shareName || !item.path.hasPrefix(current.path) {
            return nil
        }
        
        let memoryCacheKey = "\(item.shareName)::\(item.path)_thumb_\(Int(maxDimension))" as NSString
        if let cached = await worker.getCachedThumbnail(forKey: memoryCacheKey) {
            return cached
        }
        
        // Video thumbnail streaming & caching
        if item.isVideo {
            let diskKey = MediaCacheManager.shared.cacheKey(for: item.shareName, path: "\(item.path)_vidstream_v7", dimension: maxDimension)
            if let diskCached = MediaCacheManager.shared.getThumbnail(for: diskKey) {
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
            
            // 3. Fallback placeholder (do NOT persist to disk, so it retries on next view)
            let placeholder = MediaCacheManager.shared.generateVideoPlaceholder(for: item, maxDimension: maxDimension)
            await worker.cacheThumbnail(placeholder, forKey: memoryCacheKey)
            return placeholder
        }
        
        return await worker.fetchThumbnail(for: item, expectedFolderID: currentActive, maxDimension: maxDimension)
    }
    
    /// Streams minimal byte slices on demand using the same progressive loader as the player to extract a keyframe
    private func streamVideoThumbnail(for item: SMBItem, maxDimension: CGFloat) async -> UIImage? {
        if Task.isCancelled { return nil }
        
        return await videoThumbnailLimiter.withPermit {
            if Task.isCancelled { return nil }
            
            var validItem = item
            if validItem.size <= 0 {
                let realSize = await fetchFileSize(for: item)
                if realSize > 0 {
                    validItem = SMBItem(
                        name: item.name,
                        shareName: item.shareName,
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
            let delegate = SMBResourceLoaderDelegate(manager: self, item: validItem)
            let queue = DispatchQueue(label: "com.acme.ios.photos.thumbstream.\(uniqueID)", qos: .userInitiated)
            asset.resourceLoader.setDelegate(delegate, queue: queue)
            
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxDimension * 2, height: maxDimension * 2)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 2.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 2.5, preferredTimescale: 600)
            
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    Task {
                        var resumed = false
                        
                        let timeoutTask = Task {
                            try? await Task.sleep(for: .seconds(20.0))
                            if !resumed {
                                resumed = true
                                delegate.cancelAll()
                                continuation.resume(returning: nil)
                            }
                        }
                        
                        // 1. Try 5.0s frame first (avoids blank/black intro frames and gives a representative preview)
                        do {
                            let (cgImage, _) = try await generator.image(at: CMTime(seconds: 5.0, preferredTimescale: 600))
                            timeoutTask.cancel()
                            if !resumed {
                                resumed = true
                                delegate.cancelAll()
                                continuation.resume(returning: UIImage(cgImage: cgImage))
                                return
                            }
                        } catch {
                            // 2. Fallback: try .zero or 0.5s if video is shorter than 5s or 5.0s is unavailable
                            generator.requestedTimeToleranceBefore = .positiveInfinity
                            generator.requestedTimeToleranceAfter = .positiveInfinity
                            do {
                                let (cgImage, _) = try await generator.image(at: .zero)
                                timeoutTask.cancel()
                                if !resumed {
                                    resumed = true
                                    delegate.cancelAll()
                                    continuation.resume(returning: UIImage(cgImage: cgImage))
                                    return
                                }
                            } catch {
                                do {
                                    let (cgImage, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
                                    timeoutTask.cancel()
                                    if !resumed {
                                        resumed = true
                                        delegate.cancelAll()
                                        continuation.resume(returning: UIImage(cgImage: cgImage))
                                        return
                                    }
                                } catch {
                                    print("⚠️ [SMB] Thumbnail extraction failed for \(validItem.name) (\(validItem.formattedSize)): \(error.localizedDescription)")
                                }
                            }
                        }
                        
                        timeoutTask.cancel()
                        if !resumed {
                            resumed = true
                            delegate.cancelAll()
                            continuation.resume(returning: nil)
                        }
                    }
                }
            } onCancel: {
                delegate.cancelAll()
            }
        }
    }
    
    public func downloadImage(for item: SMBItem) async -> UIImage? {
        if Task.isCancelled || item.isVideo { return nil }
        return await worker.fetchFullImage(for: item)
    }
    
    public func fetchFileSize(for item: SMBItem) async -> Int64 {
        await worker.fetchFileSize(for: item)
    }
    
    public func fetchMetadata(for item: SMBItem) async -> PictureEXIFData? {
        if Task.isCancelled { return nil }
        return await worker.fetchMetadata(for: item)
    }
    
    // MARK: - Video Support & Disk Cache (Tier 3)
    
    public func fetchMediaRange(for item: SMBItem, offset: Int64, length: Int) async throws -> Data {
        try await worker.fetchMediaRange(for: item, offset: offset, length: length)
    }
    
    public func fetchVideoURL(for item: SMBItem, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        try await worker.fetchVideoURL(for: item, progress: progress)
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
    
    public func disconnect() {
        loadFolderTask?.cancel()
        loadFolderTask = nil
        activeFolderID = nil
        
        isConnected = false
        folderTree = []
        currentFolders = []
        selectedFolder = nil
        pictures = []
        
        Task {
            await worker.setActiveFolder(id: nil)
            await worker.disconnect()
        }
    }
}
