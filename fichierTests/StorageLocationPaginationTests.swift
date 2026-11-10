//
//  StorageLocationPaginationTests.swift
//  fichierTests
//
//  Tests bounded folder/tree pagination, retry deduplication, cancellation, and stale-page rejection.
//

#if DEBUG
import Foundation
import Testing
import FichierKit
@testable import fichier

@Suite("StorageLocationManager Bounded Folder Pagination Tests")
@MainActor
struct StorageLocationPaginationTests {

    private func makeConnectedManager(
        client: MockSMBClient,
        shares: [String] = ["Media", "Other"],
        folderPageSize: Int = 2
    ) async -> (manager: StorageLocationManager, suiteName: String, defaults: UserDefaults) {
        await client.updateShares(shares)
        let suiteName = "com.acme.ios.fichier.tests.pagination.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let passwordStore = SMBPasswordStore(service: "com.acme.ios.fichier.tests.\(UUID().uuidString)")
        let store = StorageLocationPersistenceStore(userDefaults: defaults, passwordStore: passwordStore)
        let worker = SMBClientActor { _, _ in client }
        let manager = StorageLocationManager(
            worker: worker,
            persistenceStore: store,
            folderPageSize: folderPageSize
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

    @Test("Initial folder load uses bounded pageSize and incrementally loads remaining pages")
    func incrementalPaginationAppendsPagesWithStableIdentities() async throws {
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
        let (manager, suiteName, defaults) = await makeConnectedManager(client: client, folderPageSize: 2)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let targetFolder = MediaItem(
            locationID: "alice@nas.local",
            name: "BigFolder",
            rootName: "Media",
            path: "/BigFolder",
            isDirectory: true
        )

        await manager.selectAndLoadFolder(targetFolder)

        // Page 0 holds the two subfolders (folder-first sorting) and leaves remaining media for next pages
        #expect(!manager.isLoading)
        #expect(!manager.isLoadingMore)
        #expect(manager.canLoadMorePages)
        #expect(manager.currentFolders.map(\.name) == ["SubA", "SubB"])
        #expect(manager.pictures.isEmpty)

        let callsAfterInitial = await client.listDirectoryPageCalls
        #expect(callsAfterInitial.count == 1)
        #expect(callsAfterInitial.first?.pageSize == 2)
        #expect(callsAfterInitial.first?.cursor == nil)
        #expect(await client.listDirectoryCalls.isEmpty)

        await manager.loadNextFolderPage()
        #expect(!manager.isLoading)
        #expect(!manager.isLoadingMore)
        #expect(manager.canLoadMorePages)
        #expect(manager.pictures.map(\.name) == ["photo01.jpg", "photo02.jpg"])

        let firstPageIDs = manager.pictures.map(\.id)

        await manager.loadNextFolderPage()
        #expect(!manager.isLoading)
        #expect(!manager.isLoadingMore)
        #expect(!manager.canLoadMorePages)
        #expect(manager.pictures.map(\.name) == ["photo01.jpg", "photo02.jpg", "photo03.jpg", "photo04.jpg"])

        // Previously loaded IDs stay identical after subsequent pages append
        #expect(Array(manager.pictures.prefix(2).map(\.id)) == firstPageIDs)

        let allCalls = await client.listDirectoryPageCalls
        #expect(allCalls.map(\.cursor) == [nil, "2", "4"])
        #expect(allCalls.allSatisfy { $0.pageSize == 2 })
    }

    @Test("Retry after failed pagination page preserves prior items and avoids duplicates")
    func retryAfterPaginationErrorPreservesStateAndDeduplicates() async {
        let contents: [String: [MediaSourceItem]] = [
            "Media/RetryFolder": [
                makeImageItem(path: "RetryFolder/01.jpg"),
                makeImageItem(path: "RetryFolder/02.jpg"),
                makeImageItem(path: "RetryFolder/03.jpg"),
                makeImageItem(path: "RetryFolder/04.jpg")
            ]
        ]
        let client = MockSMBClient(directoryContents: contents)
        await client.setPageError(SMBError.timeout, forKey: "Media/RetryFolder", cursor: "2")

        let (manager, suiteName, defaults) = await makeConnectedManager(client: client, folderPageSize: 2)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let targetFolder = MediaItem(
            locationID: "alice@nas.local",
            name: "RetryFolder",
            rootName: "Media",
            path: "/RetryFolder",
            isDirectory: true
        )

        await manager.selectAndLoadFolder(targetFolder)
        #expect(manager.pictures.map(\.name) == ["01.jpg", "02.jpg"])
        #expect(manager.canLoadMorePages)

        let initialIDs = manager.pictures.map(\.id)

        // Page 1 fails; existing items and cursor must remain intact
        await manager.loadNextFolderPage()
        #expect(!manager.isLoadingMore)
        #expect(manager.canLoadMorePages)
        #expect(manager.paginationErrorMessage != nil)
        #expect(manager.errorMessage == nil)
        #expect(manager.pictures.map(\.name) == ["01.jpg", "02.jpg"])

        // Clear transient error and retry exact same page
        await client.setPageError(nil, forKey: "Media/RetryFolder", cursor: "2")
        await manager.loadNextFolderPage()

        #expect(!manager.isLoadingMore)
        #expect(!manager.canLoadMorePages)
        #expect(manager.paginationErrorMessage == nil)
        #expect(manager.pictures.map(\.name) == ["01.jpg", "02.jpg", "03.jpg", "04.jpg"])
        #expect(Set(manager.pictures.map(\.id)).count == 4)
        #expect(Array(manager.pictures.prefix(2).map(\.id)) == initialIDs)
    }

    @Test("Cancelling in-flight next page resets isLoadingMore without losing loaded items or cursor")
    func cancellingLoadNextPagePreservesCursorAndExistingItems() async {
        let contents: [String: [MediaSourceItem]] = [
            "Media/CancelFolder": [
                makeImageItem(path: "CancelFolder/01.jpg"),
                makeImageItem(path: "CancelFolder/02.jpg"),
                makeImageItem(path: "CancelFolder/03.jpg")
            ]
        ]
        let client = MockSMBClient(directoryContents: contents)
        let (manager, suiteName, defaults) = await makeConnectedManager(client: client, folderPageSize: 2)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let targetFolder = MediaItem(
            locationID: "alice@nas.local",
            name: "CancelFolder",
            rootName: "Media",
            path: "/CancelFolder",
            isDirectory: true
        )

        await manager.selectAndLoadFolder(targetFolder)
        #expect(manager.pictures.map(\.name) == ["01.jpg", "02.jpg"])
        #expect(manager.canLoadMorePages)

        await client.armDirectoryGate(forKey: "Media/CancelFolder|2")
        let nextPageTask = Task {
            await manager.loadNextFolderPage()
        }
        await client.waitUntilDirectoryFetchStarts(forKey: "Media/CancelFolder|2")
        #expect(manager.isLoadingMore)
        #expect(!manager.isLoading)

        nextPageTask.cancel()
        await client.releaseDirectoryGate(forKey: "Media/CancelFolder|2")
        await nextPageTask.value

        #expect(!manager.isLoadingMore)
        #expect(manager.canLoadMorePages)
        #expect(manager.paginationErrorMessage == nil)
        #expect(manager.pictures.map(\.name) == ["01.jpg", "02.jpg"])

        // Following retry succeeds using preserved cursor
        await manager.loadNextFolderPage()
        #expect(!manager.canLoadMorePages)
        #expect(manager.pictures.map(\.name) == ["01.jpg", "02.jpg", "03.jpg"])
    }

    @Test("Switching folders or changing global sort rejects stale in-flight pagination pages")
    func staleNextPageDiscardedOnFolderSwitchAndSortChange() async {
        let contents: [String: [MediaSourceItem]] = [
            "Media/FolderA": [
                makeImageItem(path: "FolderA/a1.jpg", size: 100),
                makeImageItem(path: "FolderA/a2.jpg", size: 300),
                makeImageItem(path: "FolderA/a3.jpg", size: 200)
            ],
            "Media/FolderB": [
                makeImageItem(path: "FolderB/b1.jpg", size: 500)
            ]
        ]
        let client = MockSMBClient(directoryContents: contents)
        let (manager, suiteName, defaults) = await makeConnectedManager(client: client, folderPageSize: 2)
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

        await manager.selectAndLoadFolder(folderA)
        #expect(manager.pictures.map(\.name) == ["a1.jpg", "a2.jpg"])

        // Gate page 1 of FolderA, then change sort order before releasing stale page 1
        await client.armDirectoryGate(forKey: "Media/FolderA|2")
        let staleSortPageTask = Task {
            await manager.loadNextFolderPage()
        }
        await client.waitUntilDirectoryFetchStarts(forKey: "Media/FolderA|2")

        await manager.applySort(key: .size, order: .descending)
        #expect(manager.pictures.map(\.name) == ["a2.jpg", "a3.jpg"])
        #expect(manager.canLoadMorePages)

        await client.releaseDirectoryGate(forKey: "Media/FolderA|2")
        await staleSortPageTask.value

        // Stale name-sorted page 1 did not contaminate size-sorted results
        #expect(manager.pictures.map(\.name) == ["a2.jpg", "a3.jpg"])

        // Now gate page 1 of size-sorted FolderA and switch to FolderB
        await client.armDirectoryGate(forKey: "Media/FolderA|2")
        let staleFolderPageTask = Task {
            await manager.loadNextFolderPage()
        }
        await client.waitUntilDirectoryFetchStarts(forKey: "Media/FolderA|2")

        await manager.selectAndLoadFolder(folderB)
        #expect(manager.pictures.map(\.name) == ["b1.jpg"])
        #expect(!manager.canLoadMorePages)

        await client.releaseDirectoryGate(forKey: "Media/FolderA|2")
        await staleFolderPageTask.value

        #expect(manager.selectedFolder?.id == folderB.id)
        #expect(manager.pictures.map(\.name) == ["b1.jpg"])
        #expect(!manager.isLoadingMore)
    }

    @Test("loadNextFolderPageIfNeeded only triggers near trailing threshold")
    func loadNextFolderPageIfNeededTriggersNearEnd() async {
        let contents: [String: [MediaSourceItem]] = [
            "Media/ScrollFolder": (1...6).map { index in
                makeImageItem(path: String(format: "ScrollFolder/img%02d.jpg", index))
            }
        ]
        let client = MockSMBClient(directoryContents: contents)
        let (manager, suiteName, defaults) = await makeConnectedManager(client: client, folderPageSize: 4)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folder = MediaItem(
            locationID: "alice@nas.local",
            name: "ScrollFolder",
            rootName: "Media",
            path: "/ScrollFolder",
            isDirectory: true
        )

        await manager.selectAndLoadFolder(folder)
        #expect(manager.pictures.count == 4)

        guard let firstItem = manager.pictures.first, let lastItem = manager.pictures.last else {
            Issue.record("Expected initial page items")
            return
        }

        // Far from end with thresholdOffset = 1 -> no pagination triggered
        manager.loadNextFolderPageIfNeeded(currentItem: firstItem, thresholdOffset: 1)
        #expect(!manager.isLoadingMore)
        #expect((await client.listDirectoryPageCalls).count == 1)

        // Last item within thresholdOffset = 1 triggers page 1
        await client.armDirectoryGate(forKey: "Media/ScrollFolder|4")
        manager.loadNextFolderPageIfNeeded(currentItem: lastItem, thresholdOffset: 1)
        await client.waitUntilDirectoryFetchStarts(forKey: "Media/ScrollFolder|4")
        #expect(manager.isLoadingMore)

        await client.releaseDirectoryGate(forKey: "Media/ScrollFolder|4")
        while manager.isLoadingMore {
            await Task.yield()
        }

        #expect(manager.pictures.count == 6)
        #expect(!manager.canLoadMorePages)
    }

    @Test("Sidebar tree expansion relies on folder-first pages and stops once media files appear")
    func treeExpansionStopsWhenMediaPagesBegin() async {
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
        let (manager, suiteName, defaults) = await makeConnectedManager(client: client, folderPageSize: 3)
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
        // FichierKit's folder-first page is [Sub1, Sub2, pic01]. Once media appears,
        // no later page can contain another folder, so trailing media pages are not requested.
        #expect(calls.count == 1)
        #expect(manager.folderTree.first?.children?.map(\.name) == ["Sub1", "Sub2"])
    }
}
#endif
