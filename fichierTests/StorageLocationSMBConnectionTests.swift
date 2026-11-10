//
//  StorageLocationSMBConnectionTests.swift
//  fichierTests
//
//  Created for testing StorageLocationManager SMB connection, error mapping, and persistence flows.
//

#if DEBUG
import Foundation
import Testing
import UIKit
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
        #expect(failingManager.currentConnectionID.isEmpty)
        #expect(await failingClient.disconnectCalls == 1)

        // Empty shares response does not connect or persist, and disconnects ephemeral client
        let emptyClient = MockSMBClient(shares: [])
        let emptyManager = StorageLocationManager(worker: SMBClientActor { _, _ in emptyClient }, persistenceStore: store)

        await emptyManager.connect(host: "192.168.1.78", user: "bob", pass: "ok")

        #expect(!emptyManager.isConnected)
        #expect(!emptyManager.isLoading)
        #expect(emptyManager.errorMessage != nil)
        #expect(emptyManager.savedConnections.isEmpty)
        #expect(emptyManager.currentConnectionID.isEmpty)
        #expect(emptyManager.folderTree.isEmpty)
        #expect(await emptyClient.disconnectCalls >= 1)
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

    @Test("SMBClientActor disconnect invokes protocol disconnect on injected client even under cancellation")
    func workerDisconnectCallsProtocolOnInjectedClient() async throws {
        let client = MockSMBClient(shares: ["Photos"])
        let worker = SMBClientActor { _, _ in client }
        let server = SavedSMBConnection(host: "192.168.1.55", username: "alice", lastConnected: Date())

        let shares = try await worker.connectAndListShares(server: server, password: "pw", connectionID: "alice@192.168.1.55")
        #expect(shares.count == 1)
        #expect(await worker.activeClient() != nil)

        worker.cacheThumbnail(UIImage(), forKey: "sample_thumb" as NSString)
        #expect(worker.getCachedThumbnail(forKey: "sample_thumb" as NSString) != nil)

        var streamContinuation: AsyncStream<Void>.Continuation?
        let gateStream = AsyncStream<Void> { continuation in
            streamContinuation = continuation
        }
        let cancelledDisconnectTask = Task {
            for await _ in gateStream { break }
            await worker.disconnect()
        }
        cancelledDisconnectTask.cancel()
        streamContinuation?.finish()
        await cancelledDisconnectTask.value

        #expect(await client.disconnectCalls == 1)
        #expect(await client.disconnectObservedCancelled == [false])
        #expect(await worker.activeClient() == nil)
        #expect(worker.getCachedThumbnail(forKey: "sample_thumb" as NSString) == nil)
        await #expect(throws: URLError.self) {
            _ = try await worker.refreshShares()
        }
    }

    @Test("Replacing SMB session disconnects previous client and cleans up if replacement fails")
    func replacingSessionDisconnectsPreviousAndFailedReplacement() async throws {
        let client1 = MockSMBClient(shares: ["ShareOne"])
        let client2 = MockSMBClient(shares: ["ShareTwo"])
        let client3 = MockSMBClient(sharesError: SMBError.badCredentials)

        let worker = SMBClientActor { server, _ in
            switch server.host {
            case "nas1.local": return client1
            case "nas2.local": return client2
            default: return client3
            }
        }
        let server1 = SavedSMBConnection(host: "nas1.local", username: "alice", lastConnected: Date())
        let server2 = SavedSMBConnection(host: "nas2.local", username: "alice", lastConnected: Date())
        let server3 = SavedSMBConnection(host: "nas3.local", username: "alice", lastConnected: Date())

        let firstShares = try await worker.connectAndListShares(server: server1, password: "pw", connectionID: "c1")
        #expect(firstShares.map(\.name) == ["ShareOne"])
        #expect(await client1.disconnectCalls == 0)

        let secondShares = try await worker.connectAndListShares(server: server2, password: "pw", connectionID: "c2")
        #expect(secondShares.map(\.name) == ["ShareTwo"])
        #expect(await client1.disconnectCalls == 1)
        #expect(await client1.disconnectObservedCancelled == [false])
        #expect(await client2.disconnectCalls == 0)
        #expect(await worker.activeClient() != nil)

        do {
            _ = try await worker.connectAndListShares(server: server3, password: "bad", connectionID: "c3")
            Issue.record("Expected replacement connection to throw")
        } catch {
            #expect(error is SMBError)
        }

        #expect(await client2.disconnectCalls == 1)
        #expect(await client2.disconnectObservedCancelled == [false])
        #expect(await client3.disconnectCalls == 1)
        #expect(await client3.disconnectObservedCancelled == [false])
        #expect(await worker.activeClient() == nil)
    }

    @Test("Pre-cancelled replacement disconnects previous client without creating temporary client or propagating cancellation")
    func preCancelledReplacementDisconnectsPreviousClient() async throws {
        let client1 = MockSMBClient(shares: ["ShareOne"])
        let client2 = MockSMBClient(shares: ["ShareTwo"])
        let worker = SMBClientActor { server, _ in
            server.host == "nas1.local" ? client1 : client2
        }
        let server1 = SavedSMBConnection(host: "nas1.local", username: "alice", lastConnected: Date())
        let server2 = SavedSMBConnection(host: "nas2.local", username: "alice", lastConnected: Date())

        _ = try await worker.connectAndListShares(server: server1, password: "pw", connectionID: "c1")
        worker.cacheThumbnail(UIImage(), forKey: "replace_thumb" as NSString)

        var streamContinuation: AsyncStream<Void>.Continuation?
        let gateStream = AsyncStream<Void> { continuation in
            streamContinuation = continuation
        }
        let cancelledReplaceTask = Task {
            for await _ in gateStream { break }
            _ = try await worker.connectAndListShares(server: server2, password: "pw", connectionID: "c2")
        }
        cancelledReplaceTask.cancel()
        streamContinuation?.finish()

        await #expect(throws: CancellationError.self) {
            try await cancelledReplaceTask.value
        }

        #expect(await client1.disconnectCalls == 1)
        #expect(await client1.disconnectObservedCancelled == [false])
        #expect(await client2.listSharesCalls == 0)
        #expect(await client2.disconnectCalls == 0)
        #expect(await worker.activeClient() == nil)
        #expect(worker.getCachedThumbnail(forKey: "replace_thumb" as NSString) == nil)
    }

    @Test("Cancelled in-flight replacement disconnects both previous and temporary clients without observing cancellation inside disconnect")
    func cancelledInFlightReplacementDisconnectsBothClients() async throws {
        let client1 = MockSMBClient(shares: ["ShareOne"])
        let client2 = MockSMBClient(shares: ["ShareTwo"])
        let worker = SMBClientActor { server, _ in
            server.host == "nas1.local" ? client1 : client2
        }
        let server1 = SavedSMBConnection(host: "nas1.local", username: "alice", lastConnected: Date())
        let server2 = SavedSMBConnection(host: "nas2.local", username: "alice", lastConnected: Date())

        _ = try await worker.connectAndListShares(server: server1, password: "pw", connectionID: "c1")

        await client2.armSharesGate()
        let replaceTask = Task {
            _ = try await worker.connectAndListShares(server: server2, password: "pw", connectionID: "c2")
        }
        await client2.waitUntilListSharesStarts()
        replaceTask.cancel()

        await #expect(throws: CancellationError.self) {
            try await replaceTask.value
        }

        #expect(await client1.disconnectCalls == 1)
        #expect(await client1.disconnectObservedCancelled == [false])
        #expect(await client2.disconnectCalls == 1)
        #expect(await client2.disconnectObservedCancelled == [false])
        #expect(await worker.activeClient() == nil)
    }

    @Test("Cancelling in-flight SMB connection disconnects ephemeral client and resets manager state")
    func cancellingInFlightConnectionCleansUp() async {
        let (defaults, suiteName, _, store) = makeIsolatedPersistence()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let client1 = MockSMBClient(shares: ["Alpha", "Beta"])
        let client2 = MockSMBClient(shares: ["Gamma"])
        let worker = SMBClientActor { server, _ in
            server.host == "nas1.local" ? client1 : client2
        }
        let manager = StorageLocationManager(worker: worker, persistenceStore: store)

        await manager.connect(host: "nas1.local", user: "alice", pass: "pw1")
        #expect(manager.isConnected)
        #expect(manager.folderTree.map(\.name) == ["Alpha", "Beta"])

        await client2.armSharesGate()
        let connectTask = Task {
            await manager.connect(host: "nas2.local", user: "bob", pass: "pw2")
        }
        await client2.waitUntilListSharesStarts()
        #expect(await client1.disconnectCalls == 1)
        #expect(await client1.disconnectObservedCancelled == [false])
        #expect(manager.isLoading)

        connectTask.cancel()
        await client2.releaseSharesGate()
        await connectTask.value

        let client2CancelledFlags = await client2.disconnectObservedCancelled
        #expect(await client2.disconnectCalls >= 1)
        #expect(!client2CancelledFlags.isEmpty)
        #expect(client2CancelledFlags.allSatisfy { !$0 })
        #expect(await worker.activeClient() == nil)
        #expect(!manager.isConnected)
        #expect(!manager.isLoading)
        #expect(manager.errorMessage == nil)
        #expect(manager.folderTree.isEmpty)
        #expect(manager.currentConnectionID.isEmpty)
    }

    @Test("Pre-cancelled StorageLocationManager disconnect tears down client and clears caches without skipping disconnect")
    func preCancelledManagerDisconnectClearsStateAndDisconnectsClient() async {
        let (defaults, suiteName, _, store) = makeIsolatedPersistence()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let photoItem = MediaSourceItem(
            id: "alice@nas|Media::/photo.jpg",
            name: "photo.jpg",
            path: "Media/photo.jpg",
            type: .image,
            size: 1024,
            sourceID: "alice@nas",
            smbShare: "Media",
            smbPath: "photo.jpg"
        )
        let client = MockSMBClient(shares: ["Media"], directoryContents: ["Media": [photoItem]])
        let worker = SMBClientActor { _, _ in client }
        let manager = StorageLocationManager(worker: worker, persistenceStore: store)

        await manager.connect(host: "nas", user: "alice", pass: "pw")
        #expect(manager.isConnected)
        #expect(manager.pictures.count == 1)
        worker.cacheThumbnail(UIImage(), forKey: "manager_thumb" as NSString)

        var streamContinuation: AsyncStream<Void>.Continuation?
        let gateStream = AsyncStream<Void> { continuation in
            streamContinuation = continuation
        }
        let cancelledTask = Task { @MainActor in
            for await _ in gateStream { break }
            await manager.disconnect()
        }
        cancelledTask.cancel()
        streamContinuation?.finish()
        await cancelledTask.value

        #expect(await client.disconnectCalls == 1)
        #expect(await client.disconnectObservedCancelled == [false])
        #expect(await worker.activeClient() == nil)
        #expect(worker.getCachedThumbnail(forKey: "manager_thumb" as NSString) == nil)
        #expect(!manager.isConnected)
        #expect(manager.currentLocation == nil)
        #expect(manager.currentConnectionID.isEmpty)
        #expect(manager.folderTree.isEmpty)
        #expect(manager.pictures.isEmpty)
    }

    @Test("SMB share enumeration paginates deterministically with bounded page sizes")
    func shareEnumerationUsesBoundedPages() async throws {
        let client = MockSMBClient(shares: ["Zebra", "Alpha", "Media", "Docs", "Music"])
        let worker = SMBClientActor { _, _ in client }
        let server = SavedSMBConnection(host: "nas.local", username: "alice", lastConnected: Date())

        let initialShares = try await worker.connectAndListShares(
            server: server,
            password: "pw",
            connectionID: "alice@nas.local",
            sharePageSize: 2
        )
        #expect(initialShares.map(\.name) == ["Alpha", "Docs", "Media", "Music", "Zebra"])

        let refreshed = try await worker.refreshShares(pageSize: 2)
        #expect(refreshed.map(\.name) == ["Alpha", "Docs", "Media", "Music", "Zebra"])
    }
}
#endif
