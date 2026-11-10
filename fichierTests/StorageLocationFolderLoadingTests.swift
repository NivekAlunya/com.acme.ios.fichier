//
//  StorageLocationFolderLoadingTests.swift
//  fichierTests
//
//  Created for testing media folder loading, stale-request protection, cancellation, and loading cleanup.
//

#if DEBUG
import Foundation
import Testing
import FichierKit
@testable import fichier

@Suite("StorageLocationManager Folder Loading, Stale Protection & Cancellation Tests")
@MainActor
struct StorageLocationFolderLoadingTests {

    private func makeConnectedSMBManager(
        client: MockSMBClient,
        shares: [String] = ["Media"]
    ) async -> (manager: StorageLocationManager, suiteName: String, defaults: UserDefaults) {
        await client.updateShares(shares)
        let suiteName = "com.acme.ios.fichier.tests.folderload.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let passwordStore = SMBPasswordStore(service: "com.acme.ios.fichier.tests.\(UUID().uuidString)")
        let store = StorageLocationPersistenceStore(userDefaults: defaults, passwordStore: passwordStore)
        let worker = SMBClientActor { _, _ in client }
        let manager = StorageLocationManager(worker: worker, persistenceStore: store)
        await manager.connect(host: "nas.local", user: "alice", pass: "secret")
        return (manager, suiteName, defaults)
    }

    @Test("Rapid folder switch discards stale slow results and keeps latest folder items")
    func rapidSwitchProtectsAgainstStaleFolderResults() async {
        let slowFolderItem = MediaSourceItem(
            id: "slow-pic",
            name: "stale.jpg",
            path: "Media/SlowFolder/stale.jpg",
            type: .image,
            size: 100,
            smbShare: "Media",
            smbPath: "SlowFolder/stale.jpg"
        )
        let fastFolderItem = MediaSourceItem(
            id: "fast-pic",
            name: "fresh.jpg",
            path: "Media/FastFolder/fresh.jpg",
            type: .image,
            size: 200,
            smbShare: "Media",
            smbPath: "FastFolder/fresh.jpg"
        )
        let client = MockSMBClient(
            directoryContents: [
                "Media/SlowFolder": [slowFolderItem],
                "Media/FastFolder": [fastFolderItem]
            ]
        )
        let (manager, suiteName, defaults) = await makeConnectedSMBManager(client: client, shares: ["Media", "Other"])
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let slowFolder = MediaItem(
            locationID: "alice@nas.local",
            name: "SlowFolder",
            rootName: "Media",
            path: "/SlowFolder",
            isDirectory: true
        )
        let fastFolder = MediaItem(
            locationID: "alice@nas.local",
            name: "FastFolder",
            rootName: "Media",
            path: "/FastFolder",
            isDirectory: true
        )

        await client.armDirectoryGate(forKey: "Media/SlowFolder")
        let slowTask = Task {
            await manager.selectAndLoadFolder(slowFolder)
        }
        await client.waitUntilDirectoryFetchStarts(forKey: "Media/SlowFolder")
        #expect(manager.isLoading)
        #expect(manager.activeFolderID == slowFolder.id)

        // Immediately switch to fastFolder while slowFolder is suspended
        await manager.selectAndLoadFolder(fastFolder)
        #expect(manager.selectedFolder?.id == fastFolder.id)
        #expect(manager.activeFolderID == fastFolder.id)
        #expect(manager.pictures.map(\.name) == ["fresh.jpg"])
        #expect(!manager.isLoading)

        // Release slow folder gate and await stale task completion
        await client.releaseDirectoryGate(forKey: "Media/SlowFolder")
        await slowTask.value

        #expect(manager.selectedFolder?.id == fastFolder.id)
        #expect(manager.activeFolderID == fastFolder.id)
        #expect(manager.pictures.map(\.name) == ["fresh.jpg"])
        #expect(manager.errorMessage == nil)
        #expect(!manager.isLoading)
    }

    @Test("Direct cancellation of folder scan resets isLoading without surfacing error")
    func cancellationCleansUpLoadingState() async {
        let item = MediaSourceItem(
            id: "item-1",
            name: "photo.jpg",
            path: "Media/Slow/photo.jpg",
            type: .image,
            size: 100,
            smbShare: "Media",
            smbPath: "Slow/photo.jpg"
        )
        let client = MockSMBClient(directoryContents: ["Media/Slow": [item]])
        let (manager, suiteName, defaults) = await makeConnectedSMBManager(client: client, shares: ["Media", "Other"])
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folder = MediaItem(
            locationID: "alice@nas.local",
            name: "Slow",
            rootName: "Media",
            path: "/Slow",
            isDirectory: true
        )

        await client.armDirectoryGate(forKey: "Media/Slow")
        let task = Task {
            await manager.selectAndLoadFolder(folder)
        }
        await client.waitUntilDirectoryFetchStarts(forKey: "Media/Slow")
        #expect(manager.isLoading)

        task.cancel()
        await client.releaseDirectoryGate(forKey: "Media/Slow")
        await task.value

        #expect(!manager.isLoading)
        #expect(manager.errorMessage == nil)
        #expect(manager.pictures.isEmpty)
    }

    @Test("Folder scan failure surfaces error message and cleans up loading state")
    func folderLoadErrorCleansUpLoadingState() async {
        let client = MockSMBClient(directoryErrors: ["Media/Broken": SMBError.shareNotFound("Broken")])
        let (manager, suiteName, defaults) = await makeConnectedSMBManager(client: client, shares: ["Media", "Other"])
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let brokenFolder = MediaItem(
            locationID: "alice@nas.local",
            name: "Broken",
            rootName: "Media",
            path: "/Broken",
            isDirectory: true
        )

        await manager.selectAndLoadFolder(brokenFolder)

        #expect(!manager.isLoading)
        #expect(manager.errorMessage != nil)
        #expect(manager.pictures.isEmpty)
        #expect(manager.currentFolders.isEmpty)
    }

    @Test("disconnect clears loading, navigation, and selection state")
    func disconnectResetsAllState() async {
        let client = MockSMBClient()
        let (manager, suiteName, defaults) = await makeConnectedSMBManager(client: client, shares: ["Media", "Other"])
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folder = MediaItem(
            locationID: "alice@nas.local",
            name: "Gated",
            rootName: "Media",
            path: "/Gated",
            isDirectory: true
        )

        await client.armDirectoryGate(forKey: "Media/Gated")
        let task = Task {
            await manager.selectAndLoadFolder(folder)
        }
        await client.waitUntilDirectoryFetchStarts(forKey: "Media/Gated")
        #expect(manager.isLoading)

        await manager.disconnect()
        await client.releaseDirectoryGate(forKey: "Media/Gated")
        await task.value

        #expect(!manager.isConnected)
        #expect(!manager.isLoading)
        #expect(manager.folderTree.isEmpty)
        #expect(manager.currentFolders.isEmpty)
        #expect(manager.pictures.isEmpty)
        #expect(manager.selectedFolder == nil)
        #expect(manager.activeFolderID == nil)
        #expect(manager.currentConnectionID.isEmpty)
    }

    @Test("LocalStorageActor lists supported files and cleans up on invalid bookmark")
    func localStorageActorListsAndValidates() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichier_local_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let subfolder = tempRoot.appendingPathComponent("Subfolder", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try Data("img".utf8).write(to: tempRoot.appendingPathComponent("pic.jpg"))
        try Data("vid".utf8).write(to: tempRoot.appendingPathComponent("clip.mkv"))
        try Data("ignored".utf8).write(to: tempRoot.appendingPathComponent("notes.txt"))

        let suiteName = "com.acme.ios.fichier.tests.local.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let passwordStore = SMBPasswordStore(service: "com.acme.ios.fichier.tests.\(UUID().uuidString)")
        let store = StorageLocationPersistenceStore(userDefaults: defaults, passwordStore: passwordStore)
        let manager = StorageLocationManager(
            worker: SMBClientActor { _, _ in MockSMBClient() },
            persistenceStore: store
        )

        let savedLocation = try LocalStorageActor.createSavedFolderLocation(from: tempRoot)
        manager.addSavedFolderLocation(savedLocation)
        let storageLoc = StorageLocation(folder: savedLocation)

        await manager.selectLocation(storageLoc)

        #expect(manager.isConnected)
        #expect(!manager.isLoading)
        #expect(manager.errorMessage == nil)
        #expect(manager.currentFolders.map(\.name) == ["Subfolder"])
        #expect(Set(manager.pictures.map(\.name)) == Set(["pic.jpg", "clip.mkv"]))

        // Invalid bookmark resets loading and exposes localized error
        let brokenFolderLoc = SavedFolderLocation(name: "Missing", bookmarkData: Data([0x00, 0x01]), isICloud: false)
        await manager.selectLocation(StorageLocation(folder: brokenFolderLoc))
        #expect(!manager.isLoading)
        #expect(!manager.isConnected)
        #expect(manager.errorMessage != nil)
    }
}
#endif
