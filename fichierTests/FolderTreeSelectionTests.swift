//
//  FolderTreeSelectionTests.swift
//  fichierTests
//
//

import Foundation
import Testing
import FichierKit
@testable import fichier

/// Unit tests verifying folder tree selection state and drive selection gating.
@Suite("FolderTreeSelectionTests")
@MainActor
struct FolderTreeSelectionTests {
    @Test("hasSelectedDrive is false when disconnected")
    func hasSelectedDriveWhenDisconnected() {
        let manager = StorageLocationManager()
        #expect(!manager.isConnected)
        #expect(manager.currentLocation == nil)
        #expect(!manager.hasSelectedDrive)
    }

    @Test("hasSelectedDrive is false for connected SMB when no share is selected")
    func hasSelectedDriveSMBWithoutShare() {
        let manager = StorageLocationManager()
        let server = SavedSMBConnection(host: "nas.local", username: "alice", lastConnected: Date(), hostname: "nas")
        let location = StorageLocation(smb: server)
        manager.savedConnections = [server]
        manager.currentLocation = location
        manager.isConnected = true
        manager.selectedShare = nil

        let share = MediaItem(locationID: location.id, name: "Public", rootName: "Public", path: "", isDirectory: true)
        manager.folderTree = [share]

        #expect(manager.isConnected)
        #expect(!manager.hasSelectedDrive)
    }

    @Test("hasSelectedDrive is true for connected SMB once a share is selected")
    func hasSelectedDriveSMBWithShare() async {
        let manager = StorageLocationManager()
        let server = SavedSMBConnection(host: "nas.local", username: "alice", lastConnected: Date(), hostname: "nas")
        let location = StorageLocation(smb: server)
        manager.savedConnections = [server]
        manager.currentLocation = location
        manager.isConnected = true

        let share = MediaItem(locationID: location.id, name: "Public", rootName: "Public", path: "", isDirectory: true)
        manager.folderTree = [share]
        #expect(!manager.hasSelectedDrive)

        await manager.selectShare(share)
        #expect(manager.selectedShare?.name == "Public")
        #expect(manager.hasSelectedDrive)
    }

    @Test("hasSelectedDrive is true for connected local or photos location")
    func hasSelectedDriveLocalOrPhotos() {
        let manager = StorageLocationManager()
        manager.currentLocation = StorageLocation.photos
        manager.isConnected = true
        #expect(manager.hasSelectedDrive)
    }

    @Test("localized keys for unavailable content and sidebar actions")
    func localizedKeysForUnavailableContent() {
        #expect(String(localized: .Strings.folders) == "Folders")
        #expect(String(localized: .Strings.selectStorage) == "Select storage")
        #expect(String(localized: .Strings.openSidebar) == "Open Sidebar")
        #expect(String(localized: .Strings.selectStorageSidebarInstruction) == "Tap the sidebar icon to select a storage location.")
    }
}
