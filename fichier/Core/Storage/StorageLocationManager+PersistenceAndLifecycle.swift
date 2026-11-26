//
//  StorageLocationManager+PersistenceAndLifecycle.swift
//  fichier
//

import Foundation
import UIKit
import Wappn
import FichierKit

@MainActor
extension StorageLocationManager {
    // MARK: - Lifecycle & Memory Pressure Observers

    /// Registers system observers for memory warnings and background transitions.
    ///
    /// To ensure the app maintains a lean memory footprint and complies with iOS memory budgets:
    /// - `didReceiveMemoryWarningNotification` flushes volatile RAM caches in `worker`.
    /// - `didEnterBackgroundNotification` triggers a detached utility task to prune expired disk cache entries.
    func setupLifecycleObservers() {
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
            Task { @MainActor in
                let bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "MediaCacheMaintenanceSweep")
                await Task.detached(priority: .utility) {
                    MediaCacheManager.shared.performMaintenanceSweep()
                }.value
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        }
    }

    // MARK: - Cache Management

    /// Flushes in-memory folder and thumbnail caches from the underlying worker actor.
    public func clearMemoryCache() async {
        await worker.clearMemoryCache()
    }

    // MARK: - Saved Connections Persistence

    /// Loads and decodes persisted SMB connections from `UserDefaults`.
    func loadSavedConnections() {
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
    func saveValidatedConnection(host: String, user: String, pass: String, hostname: String? = nil) async {
        do {
            savedConnections = try await persistenceStore.saveValidatedConnection(
                host: host,
                user: user,
                pass: pass,
                hostname: hostname,
                existingConnections: savedConnections
            )
        } catch {
            loge("Failed to persist validated SMB connection credentials: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a saved connection record from `UserDefaults` and removes its password from Keychain.
    ///
    /// - Parameter connection: The connection to remove.
    public func removeSavedConnection(_ connection: SavedSMBConnection) async {
        savedConnections = await persistenceStore.removeSavedConnection(connection, from: savedConnections)
        if currentLocation?.smbConnection?.id == connection.id {
            await disconnect()
        }
    }

    // MARK: - Saved Folder Locations Persistence (Local & iCloud Drive)

    /// Aggregated list of all available storage locations, ordered with Photos first, followed by folders and SMB servers.
    public var allLocations: [StorageLocation] {
        [StorageLocation.photos]
            + savedFolderLocations.map { StorageLocation(folder: $0) }
            + savedConnections.map { StorageLocation(smb: $0) }
    }

    /// Loads and decodes local folder bookmarks from `UserDefaults`.
    func loadSavedFolderLocations() {
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
    public func removeSavedFolderLocation(_ location: SavedFolderLocation) async {
        savedFolderLocations = persistenceStore.removeSavedFolderLocation(location, from: savedFolderLocations)
        if currentLocation?.folderLocation?.id == location.id {
            await disconnect()
        }
    }

    /// Updates refreshed security-scoped bookmark data for an existing folder location.
    ///
    /// - Parameters:
    ///   - bookmarkData: The updated binary bookmark data.
    ///   - folderLocation: The target location record.
    func updateBookmarkData(_ bookmarkData: Data, for folderLocation: SavedFolderLocation) {
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
                await removeSavedFolderLocation(folder)
            }
        case .photos:
            break
        }
    }
}
