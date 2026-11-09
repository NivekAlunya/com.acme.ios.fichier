//
//  StorageLocationSMBConnectionTests.swift
//  fichierTests
//
//  Created for testing StorageLocationManager SMB connection, error mapping, and persistence flows.
//

#if DEBUG
import Foundation
import Testing
import FichierKit
@testable import fichier

@Suite("StorageLocationManager SMB Connection & Persistence Tests")
@MainActor
struct StorageLocationSMBConnectionTests {

    private func makeIsolatedPersistence() -> (
        defaults: UserDefaults,
        suiteName: String,
        passwordStore: SMBPasswordStore,
        store: StorageLocationPersistenceStore
    ) {
        let suiteName = "com.acme.ios.fichier.tests.smbconn.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let passwordStore = SMBPasswordStore(service: "com.acme.ios.fichier.tests.\(UUID().uuidString)")
        let store = StorageLocationPersistenceStore(userDefaults: defaults, passwordStore: passwordStore)
        return (defaults, suiteName, passwordStore, store)
    }

    @Test("Successful multi-share SMB connection updates state and persists credentials")
    func connectSuccessPersistsConnectionAndLoadsShares() async {
        let (defaults, suiteName, _, store) = makeIsolatedPersistence()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let client = MockSMBClient(shares: ["Videos", "Photos"])
        let worker = SMBClientActor { _, _ in client }
        let manager = StorageLocationManager(worker: worker, persistenceStore: store)

        await manager.connect(host: "192.168.1.50", user: "alice", pass: "s3cr3t", hostname: "MacMini")

        #expect(manager.isConnected)
        #expect(!manager.isLoading)
        #expect(manager.errorMessage == nil)
        #expect(manager.currentConnectionID == "alice@192.168.1.50")
        #expect(manager.folderTree.map(\.name) == ["Photos", "Videos"])
        #expect(manager.savedConnections.count == 1)
        #expect(manager.currentLocation?.smbConnection?.id == "alice@192.168.1.50")

        let storedPassword = await manager.password(for: manager.savedConnections[0])
        #expect(storedPassword == "s3cr3t")

        // Verify a newly initialized manager restores the persisted connection and password
        let restoredManager = StorageLocationManager(worker: SMBClientActor { _, _ in client }, persistenceStore: store)
        #expect(restoredManager.savedConnections.count == 1)
        #expect(restoredManager.savedConnections[0].hostname == "MacMini")
        let restoredPassword = await restoredManager.password(for: restoredManager.savedConnections[0])
        #expect(restoredPassword == "s3cr3t")

        // Removing the location cleans defaults, Keychain password, and disconnects active session
        if let location = manager.currentLocation {
            await manager.removeLocation(location)
        }
        await Task.yield()
        #expect(manager.savedConnections.isEmpty)
        let deletedPassword = await store.password(for: SavedSMBConnection(host: "192.168.1.50", username: "alice", lastConnected: Date()))
        #expect(deletedPassword.isEmpty)
    }

    @Test("Single-share SMB connection automatically selects and scans the share root")
    func connectSingleShareAutoLoadsFolder() async {
        let (defaults, suiteName, _, store) = makeIsolatedPersistence()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let shareItems = [
            MediaSourceItem(
                id: "alice@nas|Media::/Albums",
                name: "Albums",
                path: "Media/Albums",
                type: .folder,
                sourceID: "alice@nas",
                smbShare: "Media",
                smbPath: "Albums"
            ),
            MediaSourceItem(
                id: "alice@nas|Media::/cover.jpg",
                name: "cover.jpg",
                path: "Media/cover.jpg",
                type: .image,
                size: 1024,
                sourceID: "alice@nas",
                smbShare: "Media",
                smbPath: "cover.jpg"
            )
        ]
        let client = MockSMBClient(shares: ["Media"], directoryContents: ["Media": shareItems])
        let worker = SMBClientActor { _, _ in client }
        let manager = StorageLocationManager(worker: worker, persistenceStore: store)

        await manager.connect(host: "nas", user: "alice", pass: "pw")

        #expect(manager.isConnected)
        #expect(!manager.isLoading)
        #expect(manager.selectedFolder?.name == "Media")
        #expect(manager.currentFolders.map(\.name) == ["Albums"])
        #expect(manager.pictures.map(\.name) == ["cover.jpg"])
    }

    @Test("SMB connection failure and empty shares clean up state without saving credentials")
    func connectFailuresCleanUpState() async {
        let (defaults, suiteName, _, store) = makeIsolatedPersistence()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let failingClient = MockSMBClient(sharesError: SMBError.badCredentials)
        let failingManager = StorageLocationManager(worker: SMBClientActor { _, _ in failingClient }, persistenceStore: store)

        await failingManager.connect(host: "192.168.1.77", user: "bob", pass: "wrong")

        #expect(!failingManager.isConnected)
        #expect(!failingManager.isLoading)
        #expect(failingManager.errorMessage?.contains("Authentication failed") == true)
        #expect(failingManager.savedConnections.isEmpty)
        #expect(failingManager.folderTree.isEmpty)

        // Empty shares response does not connect or persist
        let emptyClient = MockSMBClient(shares: [])
        let emptyManager = StorageLocationManager(worker: SMBClientActor { _, _ in emptyClient }, persistenceStore: store)

        await emptyManager.connect(host: "192.168.1.78", user: "bob", pass: "ok")

        #expect(!emptyManager.isConnected)
        #expect(!emptyManager.isLoading)
        #expect(emptyManager.errorMessage != nil)
        #expect(emptyManager.savedConnections.isEmpty)
    }

    @Test("Invalid host format with explicit port fails immediately without hitting SMB client")
    func invalidHostWithPortFailsValidation() async {
        let (defaults, suiteName, _, store) = makeIsolatedPersistence()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let client = MockSMBClient(shares: ["Media"])
        let manager = StorageLocationManager(worker: SMBClientActor { _, _ in client }, persistenceStore: store)

        await manager.connect(host: "192.168.1.10:445", user: "alice", pass: "secret")

        #expect(!manager.isConnected)
        #expect(!manager.isLoading)
        #expect(manager.errorMessage != nil)
        #expect(await client.listSharesCalls == 0)
    }

    @Test("selectLocation reconnects saved SMB connection using stored Keychain password")
    func selectLocationReconnectsSavedSMB() async {
        let (defaults, suiteName, _, store) = makeIsolatedPersistence()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let saved = await store.saveValidatedConnection(
            host: "192.168.1.90",
            user: "kevin",
            pass: "keychain-pass",
            hostname: "StudioMac",
            existingConnections: []
        )
        let location = StorageLocation(smb: saved[0])

        let manager = StorageLocationManager(
            worker: SMBClientActor { _, passedPassword in
                MockSMBClient(shares: passedPassword == "keychain-pass" ? ["Photos", "Docs"] : [])
            },
            persistenceStore: store
        )

        await manager.selectLocation(location)

        #expect(manager.isConnected)
        #expect(!manager.isLoading)
        #expect(manager.errorMessage == nil)
        #expect(manager.folderTree.map(\.name) == ["Docs", "Photos"])
    }
}
#endif
