//
//  FolderTreeSynchronizationTests.swift
//  fichierTests
//
//

#if DEBUG
import Foundation
import Testing
import FichierKit
@testable import fichier

@Suite("Folder Tree Synchronization Tests")
@MainActor
struct FolderTreeSynchronizationTests {

    private func makeConnectedManager(
        client: MockSMBClient,
        shares: [String] = ["Media"]
    ) async -> (manager: StorageLocationManager, suiteName: String, defaults: UserDefaults) {
        await client.updateShares(shares)
        let suiteName = "com.acme.ios.fichier.tests.tree-sync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let passwordStore = SMBPasswordStore(service: "com.acme.ios.fichier.tests.\(UUID().uuidString)")
        let store = StorageLocationPersistenceStore(userDefaults: defaults, passwordStore: passwordStore)
        let worker = SMBClientActor { _, _ in client }
        let manager = StorageLocationManager(worker: worker, persistenceStore: store)
        await manager.connect(host: "nas.local", user: "alice", pass: "secret")
        return (manager, suiteName, defaults)
    }

    @Test("Creating a subfolder increments mutationRevision and refreshes active folder")
    func testCreateFolderIncrementsMutationRevision() async throws {
        let initialFolder = MediaSourceItem(
            id: "folder-1",
            name: "Vacation",
            path: "Media/Vacation",
            type: .folder,
            smbShare: "Media",
            smbPath: "Vacation"
        )
        let client = MockSMBClient(
            shares: ["Media"],
            directoryContents: [
                "Media/": [initialFolder],
                "Media/Vacation": []
            ]
        )
        let (manager, suiteName, defaults) = await makeConnectedManager(client: client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(manager.mutationRevision == 0)

        // Select the root share
        guard let shareRoot = manager.folderTree.first else {
            Issue.record("Expected share root in folder tree")
            return
        }
        await manager.selectAndLoadFolder(shareRoot)
        #expect(manager.currentFolders.count == 1)
        #expect(manager.currentFolders.first?.name == "Vacation")

        // Create new folder "Photos2026"
        try await manager.createFolder(named: "Photos2026", in: shareRoot)

        #expect(manager.mutationRevision == 1)
        let didCreate = await client.createdDirectories.contains(where: { $0.share == "Media" && $0.path.contains("Photos2026") })
        #expect(didCreate)
        #expect(manager.currentFolders.count == 2)
        #expect(manager.currentFolders.contains(where: { $0.name == "Photos2026" }))
    }

    @Test("Tree branch expansion is retained across mutations")
    func testTreeBranchExpansionPreservedOnMutation() async throws {
        let subfolderItem = MediaSourceItem(
            id: "sub-1",
            name: "2026",
            path: "Media/Vacation/2026",
            type: .folder,
            smbShare: "Media",
            smbPath: "Vacation/2026"
        )
        let client = MockSMBClient(
            shares: ["Media"],
            directoryContents: [
                "Media/": [
                    MediaSourceItem(
                        id: "root-sub",
                        name: "Vacation",
                        path: "Media/Vacation",
                        type: .folder,
                        smbShare: "Media",
                        smbPath: "Vacation"
                    )
                ],
                "Media/Vacation": [subfolderItem],
                "Media/Vacation/2026": []
            ]
        )
        let (manager, suiteName, defaults) = await makeConnectedManager(client: client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        guard let shareRoot = manager.folderTree.first else {
            Issue.record("Expected share root in folder tree")
            return
        }

        // Expand root share in tree
        await manager.loadSubfoldersForTree(at: shareRoot)
        let vacationNode = manager.folderTree.first?.children?.first(where: { $0.name == "Vacation" })
        #expect(vacationNode != nil)

        // Expand vacation node
        if let vacationNode {
            await manager.loadSubfoldersForTree(at: vacationNode)
        }

        let expandedVacation = manager.folderTree.first?.children?.first(where: { $0.name == "Vacation" })
        #expect(expandedVacation?.children?.count == 1)
        #expect(expandedVacation?.children?.first?.name == "2026")

        // Now perform a mutation (create folder in Vacation)
        if let vacationNode {
            try await manager.createFolder(named: "Summer", in: vacationNode)
        }

        #expect(manager.mutationRevision == 1)
        // Verify Vacation node retained its expanded children
        let vacationAfterMutation = manager.folderTree.first?.children?.first(where: { $0.name == "Vacation" })
        #expect(vacationAfterMutation?.children != nil)
        #expect(vacationAfterMutation?.children?.contains(where: { $0.name == "2026" }) == true)
        #expect(vacationAfterMutation?.children?.contains(where: { $0.name == "Summer" }) == true)
    }

    @Test("refreshExpandedTreeBranches updates all nodes that maintain loaded children")
    func testRefreshExpandedTreeBranches() async {
        let initialChild = MediaSourceItem(
            id: "child-1",
            name: "Child1",
            path: "Media/Child1",
            type: .folder,
            smbShare: "Media",
            smbPath: "Child1"
        )
        let client = MockSMBClient(
            shares: ["Media"],
            directoryContents: [
                "Media/": [initialChild]
            ]
        )
        let (manager, suiteName, defaults) = await makeConnectedManager(client: client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        guard let shareRoot = manager.folderTree.first else {
            Issue.record("Expected share root")
            return
        }

        await manager.loadSubfoldersForTree(at: shareRoot)
        #expect(manager.folderTree.first?.children?.count == 1)

        // Inject new item into client directory contents
        let newChild = MediaSourceItem(
            id: "child-2",
            name: "Child2",
            path: "Media/Child2",
            type: .folder,
            smbShare: "Media",
            smbPath: "Child2"
        )
        await client.updateDirectoryContents([initialChild, newChild], forKey: "Media")

        // Refresh expanded branches
        await manager.refreshExpandedTreeBranches()

        #expect(manager.folderTree.first?.children?.count == 2)
        #expect(manager.folderTree.first?.children?.contains(where: { $0.name == "Child2" }) == true)
    }

    @Test("renameItem updates node in tree and descendant paths while preserving siblings")
    func testRenameNodeInTreePreservesSiblingsAndUpdatesDescendants() async throws {
        let leaf = MediaSourceItem(
            id: "leaf-1",
            name: "Doc",
            path: "Media/FolderA/Sub/Doc",
            type: .document,
            smbShare: "Media",
            smbPath: "FolderA/Sub/Doc"
        )
        let sub = MediaSourceItem(
            id: "sub-1",
            name: "Sub",
            path: "Media/FolderA/Sub",
            type: .folder,
            smbShare: "Media",
            smbPath: "FolderA/Sub"
        )
        let folderA = MediaSourceItem(
            id: "folder-a",
            name: "FolderA",
            path: "Media/FolderA",
            type: .folder,
            smbShare: "Media",
            smbPath: "FolderA"
        )
        let folderB = MediaSourceItem(
            id: "folder-b",
            name: "FolderB",
            path: "Media/FolderB",
            type: .folder,
            smbShare: "Media",
            smbPath: "FolderB"
        )
        let client = MockSMBClient(
            shares: ["Media"],
            directoryContents: [
                "Media/": [folderA, folderB],
                "Media/FolderA": [sub],
                "Media/FolderA/Sub": [leaf]
            ]
        )
        let (manager, suiteName, defaults) = await makeConnectedManager(client: client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        guard let shareRoot = manager.folderTree.first else {
            Issue.record("Expected share root")
            return
        }

        // Expand root and FolderA
        await manager.loadSubfoldersForTree(at: shareRoot)
        let nodeA = manager.folderTree.first?.children?.first(where: { $0.name == "FolderA" })
        #expect(nodeA != nil)
        if let nodeA {
            await manager.loadSubfoldersForTree(at: nodeA)
        }

        // Rename FolderA -> RenamedA
        if let targetToRename = manager.folderTree.first?.children?.first(where: { $0.name == "FolderA" }) {
            let renamed = try await manager.renameItem(targetToRename, to: "RenamedA")
            #expect(renamed.name == "RenamedA")
        }

        // Verify siblings (FolderB) are preserved intact
        let children = manager.folderTree.first?.children ?? []
        #expect(children.contains(where: { $0.name == "FolderB" }))
        let renamedNode = children.first(where: { $0.name == "RenamedA" })
        #expect(renamedNode != nil)
        #expect(renamedNode?.children?.contains(where: { $0.name == "Sub" }) == true)
    }
}
#endif
