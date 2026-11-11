//
//  StorageLocationPaginationTests.swift
//  fichierTests
//
//  Tests full folder loading, cancellation, stale folder load rejection, and sidebar tree expansion.
//

#if DEBUG
import Foundation
import Testing
import FichierKit
@testable import fichier

@Suite("StorageLocationManager Folder Loading Tests")
@MainActor
struct StorageLocationPaginationTests {

    private func makeConnectedManager(
        client: MockSMBClient,
        shares: [String] = ["Media", "Other"]
    ) async -> (manager: StorageLocationManager, suiteName: String, defaults: UserDefaults) {
        await client.updateShares(shares)
        let suiteName = "com.acme.ios.fichier.tests.folderload.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let passwordStore = SMBPasswordStore(service: "com.acme.ios.fichier.tests.\(UUID().uuidString)")
        let store = StorageLocationPersistenceStore(userDefaults: defaults, passwordStore: passwordStore)
        let worker = SMBClientActor { _, _ in client }
        let manager = StorageLocationManager(
            worker: worker,
            persistenceStore: store
        )
        await manager.connect(host: "nas.local", user: "alice", pass: "secret")
        return (manager, suiteName, defaults)
    }

    private func makeFolderItem(share: String = "Media", path: String) -> MediaSourceItem {
        let name = (path as NSString).lastPathComponent
        return MediaSourceItem(
            id: "alice@nas.local|\(share)::/\(path)",
            name: name,
            path: "\(share)/\(path)",
            type: .folder,
            sourceID: "alice@nas.local",
            smbShare: share,
            smbPath: path
        )
    }

    private func makeImageItem(
        share: String = "Media",
        path: String,
        size: Int64 = 100,
        modifiedDate: Date? = nil
    ) -> MediaSourceItem {
        let name = (path as NSString).lastPathComponent
        return MediaSourceItem(
            id: "alice@nas.local|\(share)::/\(path)",
            name: name,
            path: "\(share)/\(path)",
            type: .image,
            size: size,
            modifiedDate: modifiedDate,
            sourceID: "alice@nas.local",
            smbShare: share,
            smbPath: path
        )
    }

    @Test("selectAndLoadFolder loads all subfolders and media items in a single unpaginated pass")
    func folderLoadFetchesCompleteContentsAtOnce() async throws {
        let contents: [String: [MediaSourceItem]] = [
            "Media/BigFolder": [
                makeImageItem(path: "BigFolder/photo04.jpg", size: 400),
                makeFolderItem(path: "BigFolder/SubA"),
                makeImageItem(path: "BigFolder/photo02.jpg", size: 200),
                makeFolderItem(path: "BigFolder/SubB"),
                makeImageItem(path: "BigFolder/photo01.jpg", size: 100),
                makeImageItem(path: "BigFolder/photo03.jpg", size: 300)
            ]
        ]
        let client = MockSMBClient(directoryContents: contents)
        let (manager, suiteName, defaults) = await makeConnectedManager(client: client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let targetFolder = MediaItem(
            locationID: "alice@nas.local",
            name: "BigFolder",
            rootName: "Media",
            path: "/BigFolder",
            isDirectory: true
        )

        await manager.selectAndLoadFolder(targetFolder)

        #expect(!manager.isLoading)
        #expect(manager.errorMessage == nil)
        #expect(manager.currentFolders.map(\.name) == ["SubA", "SubB"])
        #expect(manager.pictures.map(\.name) == ["photo01.jpg", "photo02.jpg", "photo03.jpg", "photo04.jpg"])

        let calls = await client.listDirectoryPageCalls
        #expect(calls.count == 1)
        #expect(calls.first?.cursor == nil)
        #expect(calls.first?.pageSize == Int.max)
    }

    @Test("Switching folders rapidly discards stale in-flight folder load results")
    func staleFolderLoadDiscardedOnFolderSwitch() async {
        let contents: [String: [MediaSourceItem]] = [
            "Media/FolderA": [
                makeImageItem(path: "FolderA/a1.jpg", size: 100),
                makeImageItem(path: "FolderA/a2.jpg", size: 300)
            ],
            "Media/FolderB": [
                makeImageItem(path: "FolderB/b1.jpg", size: 500)
            ]
        ]
        let client = MockSMBClient(directoryContents: contents)
        let (manager, suiteName, defaults) = await makeConnectedManager(client: client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folderA = MediaItem(
            locationID: "alice@nas.local",
            name: "FolderA",
            rootName: "Media",
            path: "/FolderA",
            isDirectory: true
        )
        let folderB = MediaItem(
            locationID: "alice@nas.local",
            name: "FolderB",
            rootName: "Media",
            path: "/FolderB",
            isDirectory: true
        )

        await client.armDirectoryGate(forKey: "Media/FolderA")
        let folderATask = Task {
            await manager.selectAndLoadFolder(folderA)
        }
        await client.waitUntilDirectoryFetchStarts(forKey: "Media/FolderA")

        await manager.selectAndLoadFolder(folderB)
        #expect(manager.selectedFolder?.id == folderB.id)
        #expect(manager.pictures.map(\.name) == ["b1.jpg"])

        await client.releaseDirectoryGate(forKey: "Media/FolderA")
        await folderATask.value

        #expect(manager.selectedFolder?.id == folderB.id)
        #expect(manager.pictures.map(\.name) == ["b1.jpg"])
        #expect(!manager.isLoading)
    }

    @Test("Sidebar tree expansion populates child subfolders without altering active selection")
    func treeExpansionLoadsSubfolders() async {
        var items: [MediaSourceItem] = [
            makeFolderItem(path: "DeepTree/Sub1"),
            makeFolderItem(path: "DeepTree/Sub2")
        ]
        items.append(contentsOf: (1...12).map { index in
            makeImageItem(path: String(format: "DeepTree/pic%02d.jpg", index))
        })

        let client = MockSMBClient(
            shares: ["Media", "Other"],
            directoryContents: ["Media/DeepTree": items]
        )
        let (manager, suiteName, defaults) = await makeConnectedManager(client: client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let parent = MediaItem(
            locationID: "alice@nas.local",
            name: "DeepTree",
            rootName: "Media",
            path: "/DeepTree",
            isDirectory: true
        )
        manager.folderTree = [parent]

        await manager.loadSubfoldersForTree(at: parent)

        let calls = await client.listDirectoryPageCalls
        #expect(calls.count == 1)
        #expect(manager.folderTree.first?.children?.map(\.name) == ["Sub1", "Sub2"])
    }
}
#endif
