//
//  FileOperationsTests.swift
//  fichierTests
//

#if DEBUG && canImport(XCTest)
import XCTest
@testable import fichier
import FichierKit

final class FileOperationsTests: XCTestCase {
    
    private var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirectory = dir
    }
    
    override func tearDown() async throws {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        try await super.tearDown()
    }
    
    func testCreateFolderSuccess() async throws {
        let actor = LocalStorageActor()
        let rootItem = MediaItem(
            locationID: "test_loc",
            name: "TempRoot",
            rootName: "TempRoot",
            path: "",
            isDirectory: true,
            localURL: tempDirectory
        )
        
        let createdFolder = try await actor.createFolder(named: "NewSubfolder", in: rootItem, locationID: "test_loc")
        
        XCTAssertEqual(createdFolder.name, "NewSubfolder")
        XCTAssertTrue(createdFolder.isDirectory)
        XCTAssertEqual(createdFolder.path, "NewSubfolder")
        let localURL = try XCTUnwrap(createdFolder.localURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localURL.path))
    }
    
    func testCreateFolderInvalidNames() async {
        let actor = LocalStorageActor()
        let rootItem = MediaItem(
            locationID: "test_loc",
            name: "TempRoot",
            rootName: "TempRoot",
            path: "",
            isDirectory: true,
            localURL: tempDirectory
        )
        
        do {
            _ = try await actor.createFolder(named: "  ", in: rootItem, locationID: "test_loc")
            XCTFail("Expected invalid name error for whitespace")
        } catch let error as FileOperationError {
            if case .invalidName = error {
                // Success
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        
        do {
            _ = try await actor.createFolder(named: "Invalid/Name", in: rootItem, locationID: "test_loc")
            XCTFail("Expected invalid name error for slashes")
        } catch let error as FileOperationError {
            if case .invalidName = error {
                // Success
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        
        do {
            _ = try await actor.createFolder(named: "..", in: rootItem, locationID: "test_loc")
            XCTFail("Expected invalid name error for parent traversal ..")
        } catch let error as FileOperationError {
            if case .invalidName = error {
                // Success
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        
        do {
            _ = try await actor.createFolder(named: ".", in: rootItem, locationID: "test_loc")
            XCTFail("Expected invalid name error for current directory .")
        } catch let error as FileOperationError {
            if case .invalidName = error {
                // Success
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testCreateFolderAlreadyExists() async throws {
        let actor = LocalStorageActor()
        let rootItem = MediaItem(
            locationID: "test_loc",
            name: "TempRoot",
            rootName: "TempRoot",
            path: "",
            isDirectory: true,
            localURL: tempDirectory
        )
        
        _ = try await actor.createFolder(named: "ExistingFolder", in: rootItem, locationID: "test_loc")
        
        do {
            _ = try await actor.createFolder(named: "ExistingFolder", in: rootItem, locationID: "test_loc")
            XCTFail("Expected already exists error")
        } catch let error as FileOperationError {
            if case .itemAlreadyExists = error {
                // Success
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testMoveItemSuccess() async throws {
        let actor = LocalStorageActor()
        
        // Setup source and destination directories
        let folderA = tempDirectory.appendingPathComponent("FolderA", isDirectory: true)
        let folderB = tempDirectory.appendingPathComponent("FolderB", isDirectory: true)
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        
        let fileURL = folderA.appendingPathComponent("test.txt")
        try "sample content".write(to: fileURL, atomically: true, encoding: .utf8)
        
        let itemToMove = MediaItem(
            locationID: "test_loc",
            name: "test.txt",
            rootName: "TempRoot",
            path: "FolderA/test.txt",
            isDirectory: false,
            localURL: fileURL
        )
        
        let destFolderItem = MediaItem(
            locationID: "test_loc",
            name: "FolderB",
            rootName: "TempRoot",
            path: "FolderB",
            isDirectory: true,
            localURL: folderB
        )
        
        try await actor.moveItems([itemToMove], to: destFolderItem)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let targetPath = folderB.appendingPathComponent("test.txt").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetPath))
    }
    
    func testMoveFolderCannotMoveIntoSelf() async throws {
        let actor = LocalStorageActor()
        
        let folderA = tempDirectory.appendingPathComponent("FolderA", isDirectory: true)
        let subFolder = folderA.appendingPathComponent("SubFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)
        
        let itemA = MediaItem(
            locationID: "test_loc",
            name: "FolderA",
            rootName: "TempRoot",
            path: "FolderA",
            isDirectory: true,
            localURL: folderA
        )
        
        let subItem = MediaItem(
            locationID: "test_loc",
            name: "SubFolder",
            rootName: "TempRoot",
            path: "FolderA/SubFolder",
            isDirectory: true,
            localURL: subFolder
        )
        
        // Cannot move into self
        do {
            try await actor.moveItems([itemA], to: itemA)
            XCTFail("Expected cannotMoveIntoSelf error")
        } catch let error as FileOperationError {
            if case .cannotMoveIntoSelf = error {
                // Success
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        // Cannot move into child subfolder
        do {
            try await actor.moveItems([itemA], to: subItem)
            XCTFail("Expected cannotMoveIntoSelf error")
        } catch let error as FileOperationError {
            if case .cannotMoveIntoSelf = error {
                // Success
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testMoveItemsDuplicateFilenameBatchFails() async throws {
        let actor = LocalStorageActor()
        
        let folder1 = tempDirectory.appendingPathComponent("Folder1", isDirectory: true)
        let folder2 = tempDirectory.appendingPathComponent("Folder2", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("DestFolder", isDirectory: true)
        
        try FileManager.default.createDirectory(at: folder1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        
        let file1 = folder1.appendingPathComponent("conflict.txt")
        let file2 = folder2.appendingPathComponent("conflict.txt")
        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        try "content2".write(to: file2, atomically: true, encoding: .utf8)
        
        let item1 = MediaItem(name: "conflict.txt", path: "Folder1/conflict.txt", isDirectory: false, localURL: file1)
        let item2 = MediaItem(name: "conflict.txt", path: "Folder2/conflict.txt", isDirectory: false, localURL: file2)
        let destItem = MediaItem(name: "DestFolder", path: "DestFolder", isDirectory: true, localURL: destFolder)
        
        do {
            try await actor.moveItems([item1, item2], to: destItem)
            XCTFail("Expected itemAlreadyExists error for intra-batch collision")
        } catch let error as FileOperationError {
            if case .itemAlreadyExists(let name) = error {
                XCTAssertEqual(name, "conflict.txt")
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        // Ensure atomic pre-flight preserved original files
        XCTAssertTrue(FileManager.default.fileExists(atPath: file1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destFolder.appendingPathComponent("conflict.txt").path))
    }
    
    @MainActor
    func testStorageLocationManagerCapabilities() {
        let manager = StorageLocationManager()
        
        // Photos
        manager.currentLocation = StorageLocation.photos
        XCTAssertFalse(manager.canManageCurrentFolder)
        
        let photoItem = MediaItem(
            name: "photo.jpg",
            path: "",
            isDirectory: false,
            phAssetIdentifier: "123"
        )
        XCTAssertFalse(manager.canManageItem(photoItem))
        
        // Local Folder
        let savedFolder = SavedFolderLocation(name: "LocalDocs", bookmarkData: Data(), isICloud: false)
        manager.currentLocation = StorageLocation(folder: savedFolder)
        
        let localItem = MediaItem(
            name: "document.pdf",
            path: "document.pdf",
            isDirectory: false,
            localURL: URL(fileURLWithPath: "/tmp/doc.pdf")
        )
        XCTAssertTrue(manager.canManageItem(localItem))

        // SMB Location
        let smbConn = SavedSMBConnection(host: "192.168.1.10", username: "user", lastConnected: Date())
        manager.currentLocation = StorageLocation(smb: smbConn)
        
        let smbShareFolder = MediaItem(
            locationID: smbConn.id,
            name: "Media",
            rootName: "Media",
            path: "",
            isDirectory: true
        )
        manager.selectedFolder = smbShareFolder
        XCTAssertTrue(manager.canManageCurrentFolder)
        
        let smbFile = MediaItem(
            locationID: smbConn.id,
            name: "movie.mp4",
            rootName: "Media",
            path: "movie.mp4",
            isDirectory: false
        )
        XCTAssertTrue(manager.canManageItem(smbFile))
    }

    func testSMBClientActorFileOperations() async throws {
        let mockClient = MockSMBClient(shares: ["Media"])
        let server = SavedSMBConnection(host: "192.168.1.20", username: "admin", lastConnected: Date())
        let actor = SMBClientActor { _, _ in mockClient }

        _ = try await actor.connectAndListShares(server: server, password: "test")

        // Create folder
        let createdFolder = try await actor.createFolder(named: "NewFolder", inShare: "Media", atPath: "")
        XCTAssertEqual(createdFolder.name, "NewFolder")
        XCTAssertEqual(createdFolder.path, "NewFolder")
        XCTAssertTrue(createdFolder.isDirectory)
        let created = await mockClient.createdDirectories
        XCTAssertEqual(created.count, 1)

        // Move item
        let sourceFile = MediaItem(
            locationID: server.id,
            name: "photo.jpg",
            rootName: "Media",
            path: "photo.jpg",
            isDirectory: false
        )
        try await actor.moveItems([sourceFile], to: createdFolder)
        let moved = await mockClient.movedItems
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(moved.first?.from, "photo.jpg")
        XCTAssertEqual(moved.first?.to, "NewFolder/photo.jpg")

        // Delete item
        let movedFile = MediaItem(
            locationID: server.id,
            name: "photo.jpg",
            rootName: "Media",
            path: "NewFolder/photo.jpg",
            isDirectory: false
        )
        try await actor.deleteItems([movedFile])
        let removed = await mockClient.removedItems
        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(removed.first?.path, "NewFolder/photo.jpg")
    }

    @MainActor
    func testFolderPickerTreeLazyLoading() async throws {
        let actor = LocalStorageActor()
        let rootItem = MediaItem(
            locationID: "test_loc",
            name: "TempRoot",
            rootName: "TempRoot",
            path: "",
            isDirectory: true,
            localURL: tempDirectory
        )

        // Create subfolder1 and subfolder2
        let sub1 = try await actor.createFolder(named: "FolderA", in: rootItem, locationID: "test_loc")
        _ = try await actor.createFolder(named: "FolderB", in: rootItem, locationID: "test_loc")
        // Create nested subfolder inside FolderA
        _ = try await actor.createFolder(named: "NestedUnderA", in: sub1, locationID: "test_loc")

        let manager = StorageLocationManager(worker: SMBClientActor(), localWorker: actor)
        let savedFolder = SavedFolderLocation(
            name: "TempRoot",
            bookmarkData: Data(),
            isICloud: false
        )
        manager.currentLocation = StorageLocation(folder: savedFolder)
        manager.folderTree = [rootItem]

        // 1. loadFolderPickerTree only loads immediate children of root (FolderA, FolderB)
        let pickerTree = try await manager.loadFolderPickerTree()
        XCTAssertEqual(pickerTree.count, 1)
        guard let rootInTree = pickerTree.first else {
            XCTFail("Missing root in picker tree")
            return
        }
        guard let rootChildren = rootInTree.children else {
            XCTFail("Missing root children")
            return
        }
        XCTAssertEqual(rootChildren.count, 2)
        let names = rootChildren.map { $0.name }.sorted()
        XCTAssertEqual(names, ["FolderA", "FolderB"])

        // Direct children have not been deeply crawled (their children are nil)
        guard let folderA = rootChildren.first(where: { $0.name == "FolderA" }) else {
            XCTFail("Missing FolderA")
            return
        }
        XCTAssertNil(folderA.children)

        // 2. Fetch subfolders for FolderA on demand
        let folderASubfolders = try await manager.fetchSubfoldersForPicker(at: folderA)
        XCTAssertEqual(folderASubfolders.count, 1)
        XCTAssertEqual(folderASubfolders.first?.name, "NestedUnderA")

        // 3. updateSubfoldersInTree attaches the lazy subfolders cleanly
        let updatedTree = manager.updateSubfoldersInTree(in: pickerTree, targetID: folderA.id, children: folderASubfolders)
        let updatedFolderA = updatedTree.first?.children?.first(where: { $0.name == "FolderA" })
        XCTAssertEqual(updatedFolderA?.children?.count, 1)
        XCTAssertEqual(updatedFolderA?.children?.first?.name, "NestedUnderA")
    }

    @MainActor
    func testDeleteItemsRemovesInPlaceWithoutFullReload() async throws {
        let actor = LocalStorageActor()
        let file1URL = tempDirectory.appendingPathComponent("photo1.jpg")
        let file2URL = tempDirectory.appendingPathComponent("photo2.jpg")
        try Data("img1".utf8).write(to: file1URL)
        try Data("img2".utf8).write(to: file2URL)

        let item1 = MediaItem(
            locationID: "test_loc",
            name: "photo1.jpg",
            path: "photo1.jpg",
            isDirectory: false,
            localURL: file1URL
        )
        let item2 = MediaItem(
            locationID: "test_loc",
            name: "photo2.jpg",
            path: "photo2.jpg",
            isDirectory: false,
            localURL: file2URL
        )

        let manager = StorageLocationManager(worker: SMBClientActor(), localWorker: actor)
        let savedFolder = SavedFolderLocation(name: "TempRoot", bookmarkData: Data(), isICloud: false)
        manager.currentLocation = StorageLocation(folder: savedFolder)
        manager.selectedFolder = MediaItem(locationID: "test_loc", name: "TempRoot", path: "", isDirectory: true, localURL: tempDirectory)
        manager.pictures = [item1, item2]

        // Delete item1
        try await manager.deleteItems([item1])

        // Assert item1 is removed from manager.pictures without wiping other items
        XCTAssertEqual(manager.pictures.count, 1)
        XCTAssertEqual(manager.pictures.first?.id, item2.id)
        XCTAssertFalse(manager.isLoading)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1URL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2URL.path))
    }

    @MainActor
    func testRemoveNodesFromTree() {
        let child1 = MediaItem(locationID: "loc", name: "Child1", rootName: "Root", path: "Child1", isDirectory: true)
        let child2 = MediaItem(locationID: "loc", name: "Child2", rootName: "Root", path: "Child2", isDirectory: true)
        let parent = MediaItem(
            locationID: "loc",
            name: "Parent",
            rootName: "Root",
            path: "",
            isDirectory: true,
            children: [child1, child2]
        )
        let root = MediaItem(
            locationID: "loc",
            name: "Root",
            rootName: "Root",
            path: "/",
            isDirectory: true,
            children: [parent]
        )
        let manager = StorageLocationManager(worker: SMBClientActor(), localWorker: LocalStorageActor())

        // 1. Remove Child1 from nested hierarchy
        let updatedTree = manager.removeNodesFromTree(in: [root], targetIDs: [child1.id])
        let remainingChildren = updatedTree.first?.children?.first?.children
        XCTAssertEqual(remainingChildren?.count, 1)
        XCTAssertEqual(remainingChildren?.first?.id, child2.id)

        // 2. Remove Root
        let emptyTree = manager.removeNodesFromTree(in: updatedTree, targetIDs: [root.id])
        XCTAssertTrue(emptyTree.isEmpty)
    }

    @MainActor
    func testUpdateSubfoldersInTreePreservesEmptyArray() {
        let folder = MediaItem(locationID: "loc", name: "EmptyFolder", rootName: "Root", path: "EmptyFolder", isDirectory: true)
        let manager = StorageLocationManager(worker: SMBClientActor(), localWorker: LocalStorageActor())

        let updatedTree = manager.updateSubfoldersInTree(in: [folder], targetID: folder.id, children: [])
        guard let updatedFolder = updatedTree.first else {
            XCTFail("Missing updated folder")
            return
        }
        XCTAssertNotNil(updatedFolder.children)
        XCTAssertEqual(updatedFolder.children?.count, 0)
    }

    func testLocalStorageActorDeleteFallbackOnNonTrashVolume() async throws {
        let actor = LocalStorageActor()
        let testFile = tempDirectory.appendingPathComponent("non_trash_test.txt")
        try Data("test".utf8).write(to: testFile)

        let item = MediaItem(
            locationID: "loc",
            name: "non_trash_test.txt",
            path: "non_trash_test.txt",
            isDirectory: false,
            localURL: testFile
        )

        try await actor.deleteItems([item])
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path))
    }

    @MainActor
    func testMoveItemsCrossStorageBoundaryFails() async {
        let manager = StorageLocationManager(worker: SMBClientActor(), localWorker: LocalStorageActor())

        let localItem = MediaItem(
            locationID: "local_loc",
            name: "file.txt",
            path: "file.txt",
            isDirectory: false,
            localURL: tempDirectory.appendingPathComponent("file.txt")
        )
        let smbItemA = MediaItem(
            locationID: "server1",
            name: "remote.jpg",
            rootName: "ShareA",
            path: "remote.jpg",
            isDirectory: false
        )
        let smbDestB = MediaItem(
            locationID: "server1",
            name: "DestFolder",
            rootName: "ShareB",
            path: "DestFolder",
            isDirectory: true
        )
        let localDest = MediaItem(
            locationID: "local_loc",
            name: "LocalDest",
            path: "LocalDest",
            isDirectory: true,
            localURL: tempDirectory.appendingPathComponent("LocalDest")
        )

        // 1. Moving local item to SMB destination must throw unsupportedStorage
        do {
            try await manager.moveItems([localItem], to: smbDestB)
            XCTFail("Expected unsupportedStorage error")
        } catch let error as FileOperationError {
            if case .unsupportedStorage = error {
                // Expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // 2. Moving SMB item from ShareA to ShareB must throw unsupportedStorage
        do {
            try await manager.moveItems([smbItemA], to: smbDestB)
            XCTFail("Expected unsupportedStorage error")
        } catch let error as FileOperationError {
            if case .unsupportedStorage = error {
                // Expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // 3. Moving SMB item to Local destination must throw unsupportedStorage
        do {
            try await manager.moveItems([smbItemA], to: localDest)
            XCTFail("Expected unsupportedStorage error")
        } catch let error as FileOperationError {
            if case .unsupportedStorage = error {
                // Expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRenameItemLocalStorage() async throws {
        let actor = LocalStorageActor()
        let fileURL = tempDirectory.appendingPathComponent("old_name.txt")
        try Data("content".utf8).write(to: fileURL)

        let item = MediaItem(
            locationID: "local_loc",
            name: "old_name.txt",
            rootName: "TempRoot",
            path: "old_name.txt",
            isDirectory: false,
            localURL: fileURL
        )

        let renamed = try await actor.renameItem(item, to: "renamed.txt")
        XCTAssertEqual(renamed.name, "renamed.txt")
        XCTAssertEqual(renamed.path, "renamed.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let newURL = try XCTUnwrap(renamed.localURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
    }

    func testRenameFolderLocalStorage() async throws {
        let actor = LocalStorageActor()
        let folderURL = tempDirectory.appendingPathComponent("OldFolder")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let item = MediaItem(
            locationID: "local_loc",
            name: "OldFolder",
            rootName: "TempRoot",
            path: "OldFolder",
            isDirectory: true,
            localURL: folderURL
        )

        let renamed = try await actor.renameItem(item, to: "NewFolder")
        XCTAssertEqual(renamed.name, "NewFolder")
        XCTAssertEqual(renamed.path, "NewFolder")
        XCTAssertTrue(renamed.isDirectory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folderURL.path))
        let newURL = try XCTUnwrap(renamed.localURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
    }

    func testRenameItemInvalidNames() async throws {
        let actor = LocalStorageActor()
        let fileURL = tempDirectory.appendingPathComponent("test.txt")
        try Data("test".utf8).write(to: fileURL)

        let item = MediaItem(
            locationID: "local_loc",
            name: "test.txt",
            rootName: "TempRoot",
            path: "test.txt",
            isDirectory: false,
            localURL: fileURL
        )

        let invalidNames = ["", "  ", "sub/folder", "invalid:name", ".", "..", "sub\\folder", "star*file", "query?file", "quote\"file", "less<file", "greater>file", "pipe|file", "trailing."]
        for invalidName in invalidNames {
            do {
                _ = try await actor.renameItem(item, to: invalidName)
                XCTFail("Expected invalidName error for '\(invalidName)'")
            } catch let error as FileOperationError {
                if case .invalidName = error {
                    // Expected
                } else {
                    XCTFail("Expected invalidName but got \(error)")
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRenameItemCollisionThrows() async throws {
        let actor = LocalStorageActor()
        let file1 = tempDirectory.appendingPathComponent("file1.txt")
        let file2 = tempDirectory.appendingPathComponent("file2.txt")
        try Data("1".utf8).write(to: file1)
        try Data("2".utf8).write(to: file2)

        let item = MediaItem(
            locationID: "local_loc",
            name: "file1.txt",
            rootName: "TempRoot",
            path: "file1.txt",
            isDirectory: false,
            localURL: file1
        )

        do {
            _ = try await actor.renameItem(item, to: "file2.txt")
            XCTFail("Expected itemAlreadyExists error")
        } catch let error as FileOperationError {
            if case .itemAlreadyExists = error {
                // Expected
            } else {
                XCTFail("Expected itemAlreadyExists but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRenameItemSMB() async throws {
        let mockClient = MockSMBClient(shares: ["Media"])
        let server = SavedSMBConnection(host: "192.168.1.50", username: "admin", lastConnected: Date())
        let actor = SMBClientActor { _, _ in mockClient }

        _ = try await actor.connectAndListShares(server: server, password: "test")

        let sourceFile = MediaItem(
            locationID: server.id,
            name: "old_photo.jpg",
            rootName: "Media",
            path: "old_photo.jpg",
            isDirectory: false
        )

        let renamed = try await actor.renameItem(sourceFile, to: "new_photo.jpg")
        XCTAssertEqual(renamed.name, "new_photo.jpg")
        XCTAssertEqual(renamed.path, "new_photo.jpg")

        let moved = await mockClient.movedItems
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(moved.first?.from, "old_photo.jpg")
        XCTAssertEqual(moved.first?.to, "new_photo.jpg")
    }

    func testRenameItemCaseOnlyLocalStorage() async throws {
        let actor = LocalStorageActor()
        let fileURL = tempDirectory.appendingPathComponent("lowercase.txt")
        try Data("case-content".utf8).write(to: fileURL)

        let item = MediaItem(
            locationID: "local_loc",
            name: "lowercase.txt",
            rootName: "TempRoot",
            path: "lowercase.txt",
            isDirectory: false,
            localURL: fileURL
        )

        let renamed = try await actor.renameItem(item, to: "LowerCase.txt")
        XCTAssertEqual(renamed.name, "LowerCase.txt")
        let newURL = try XCTUnwrap(renamed.localURL)
        XCTAssertEqual(newURL.lastPathComponent, "LowerCase.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
    }

    @MainActor
    func testRenameFolderTreeDescendantPaths() async throws {
        let folderA = tempDirectory.appendingPathComponent("FolderA")
        let subFolder = folderA.appendingPathComponent("SubFolder")
        let subSubFolder = subFolder.appendingPathComponent("SubSubFolder")
        try FileManager.default.createDirectory(at: subSubFolder, withIntermediateDirectories: true)

        let subSubFolderItem = MediaItem(
            locationID: "loc1",
            name: "SubSubFolder",
            rootName: "TempRoot",
            path: "FolderA/SubFolder/SubSubFolder",
            isDirectory: true,
            localURL: subSubFolder
        )
        let subFolderItem = MediaItem(
            locationID: "loc1",
            name: "SubFolder",
            rootName: "TempRoot",
            path: "FolderA/SubFolder",
            isDirectory: true,
            children: [subSubFolderItem],
            localURL: subFolder
        )
        let folderAItem = MediaItem(
            locationID: "loc1",
            name: "FolderA",
            rootName: "TempRoot",
            path: "FolderA",
            isDirectory: true,
            children: [subFolderItem],
            localURL: folderA
        )

        let actor = LocalStorageActor()
        let manager = StorageLocationManager(worker: SMBClientActor(), localWorker: actor)
        let savedFolder = SavedFolderLocation(name: "TempRoot", bookmarkData: Data(), isICloud: false)
        manager.currentLocation = StorageLocation(folder: savedFolder)
        manager.folderTree = [folderAItem]

        let renamed = try await manager.renameItem(folderAItem, to: "FolderB")
        XCTAssertEqual(renamed.name, "FolderB")
        XCTAssertEqual(renamed.path, "FolderB")

        let updatedTree = manager.folderTree
        let updatedRoot = try XCTUnwrap(updatedTree.first)
        XCTAssertEqual(updatedRoot.name, "FolderB")
        XCTAssertEqual(updatedRoot.path, "FolderB")

        let updatedChildren = try XCTUnwrap(updatedRoot.children)
        let updatedSub = try XCTUnwrap(updatedChildren.first)
        XCTAssertEqual(updatedSub.path, "FolderB/SubFolder")
        XCTAssertEqual(updatedSub.localURL?.lastPathComponent, "SubFolder")

        let updatedSubSub = try XCTUnwrap(updatedSub.children?.first)
        XCTAssertEqual(updatedSubSub.path, "FolderB/SubFolder/SubSubFolder")
        XCTAssertEqual(updatedSubSub.localURL?.lastPathComponent, "SubSubFolder")
    }

    func testDownloadProgressThrottler() async {
        let throttler = DownloadProgressThrottler(minimumInterval: .milliseconds(50), minimumPercentDelta: 5)
        
        // Initial micro-step
        let report0 = await throttler.shouldReport(bytes: 10, total: 1000) // 1% < 5%
        XCTAssertFalse(report0)

        // Jump to 10%
        let report10 = await throttler.shouldReport(bytes: 100, total: 1000)
        XCTAssertTrue(report10)

        // Micro-step to 11% immediately
        let report11 = await throttler.shouldReport(bytes: 110, total: 1000)
        XCTAssertFalse(report11)

        // Completion always reports
        let reportComplete = await throttler.shouldReport(bytes: 1000, total: 1000)
        XCTAssertTrue(reportComplete)
    }

    @MainActor
    func testRenameItemMigratesThumbnailCache() async throws {
        let fileURL = tempDirectory.appendingPathComponent("pic.jpg")
        try Data("dummy".utf8).write(to: fileURL)

        let item = MediaItem(
            locationID: "test_loc",
            name: "pic.jpg",
            rootName: "TempRoot",
            path: "pic.jpg",
            isDirectory: false,
            localURL: fileURL
        )

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let sampleImage = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }

        let (oldDiskKey, _, _) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: MediaCacheManager.standardThumbnailDimension,
            connectionID: item.connectionID
        )
        MediaCacheManager.shared.saveThumbnail(sampleImage, for: oldDiskKey)
        XCTAssertTrue(MediaCacheManager.shared.hasThumbnail(for: oldDiskKey))

        let worker = SMBClientActor()
        let oldMemoryKey = "\(item.id)_thumb" as NSString
        worker.cacheThumbnail(sampleImage, forKey: oldMemoryKey)
        MediaDetailStore.shared.registerDetail("100x100", for: item.id)

        let actor = LocalStorageActor()
        let manager = StorageLocationManager(worker: worker, localWorker: actor)
        let savedFolder = SavedFolderLocation(name: "TempRoot", bookmarkData: Data(), isICloud: false)
        manager.currentLocation = StorageLocation(folder: savedFolder)
        manager.pictures = [item]

        let renamed = try await manager.renameItem(item, to: "pic2.jpg")
        XCTAssertEqual(renamed.name, "pic2.jpg")
        XCTAssertEqual(renamed.path, "pic2.jpg")

        // 1. Verify thumbnail versions was incremented
        XCTAssertEqual(manager.thumbnailVersions[renamed.id], 1)

        // 2. Verify MediaDetailStore was migrated
        XCTAssertEqual(MediaDetailStore.shared.cachedDetail(for: renamed.id), "100x100")

        // 3. Verify in-memory cache was migrated
        let newMemoryKey = "\(renamed.id)_thumb" as NSString
        XCTAssertNotNil(worker.getCachedThumbnail(forKey: newMemoryKey))

        // 4. Verify disk cache was migrated
        let (newDiskKey, _, _) = MediaCacheManager.shared.thumbnailKeys(
            for: renamed.shareName,
            path: renamed.path,
            dimension: MediaCacheManager.standardThumbnailDimension,
            connectionID: renamed.connectionID
        )
        XCTAssertTrue(MediaCacheManager.shared.hasThumbnail(for: newDiskKey))

        // 5. Verify downloadThumbnail succeeds and returns migrated thumbnail
        let loaded = await manager.downloadThumbnail(for: renamed)
        XCTAssertNotNil(loaded)
    }

    @MainActor
    func testUpdateDescendantPathsDeepHierarchy() {
        let manager = StorageLocationManager()
        let locationID = UUID().uuidString
        let baseURL = tempDirectory.appendingPathComponent("NewParent", isDirectory: true)

        let leafFile = MediaItem(
            locationID: locationID,
            name: "photo.jpg",
            rootName: "Root",
            path: "OldParent/Sub/Deep/photo.jpg",
            isDirectory: false,
            localURL: tempDirectory.appendingPathComponent("OldParent/Sub/Deep/photo.jpg")
        )
        let deepFolder = MediaItem(
            locationID: locationID,
            name: "Deep",
            rootName: "Root",
            path: "OldParent/Sub/Deep",
            isDirectory: true,
            children: [leafFile],
            localURL: tempDirectory.appendingPathComponent("OldParent/Sub/Deep", isDirectory: true)
        )
        let subFolder = MediaItem(
            locationID: locationID,
            name: "Sub",
            rootName: "Root",
            path: "OldParent/Sub",
            isDirectory: true,
            children: [deepFolder],
            localURL: tempDirectory.appendingPathComponent("OldParent/Sub", isDirectory: true)
        )

        let updated = manager.updateDescendantPaths(
            in: [subFolder],
            oldPathPrefix: "OldParent",
            newPathPrefix: "NewParent",
            newParentURL: baseURL
        )

        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].path, "NewParent/Sub")
        XCTAssertEqual(updated[0].localURL, baseURL.appendingPathComponent("Sub", isDirectory: true))
        XCTAssertEqual(updated[0].children?[0].path, "NewParent/Sub/Deep")
        XCTAssertEqual(updated[0].children?[0].children?[0].path, "NewParent/Sub/Deep/photo.jpg")
        XCTAssertEqual(
            updated[0].children?[0].children?[0].localURL,
            baseURL.appendingPathComponent("Sub/Deep/photo.jpg", isDirectory: false)
        )
    }

    func testRenameItemRejectsForbiddenCharacters() async throws {
        let fileURL = tempDirectory.appendingPathComponent("valid.txt")
        try Data("hello".utf8).write(to: fileURL)

        let localActor = LocalStorageActor()
        let item = MediaItem(
            locationID: UUID().uuidString,
            name: "valid.txt",
            rootName: "Temp",
            path: "valid.txt",
            isDirectory: false,
            localURL: fileURL
        )

        let forbiddenNames = [
            "bad\\name.txt",
            "bad:name.txt",
            "bad?name.txt",
            "bad*name.txt",
            "bad/name.txt"
        ]

        for badName in forbiddenNames {
            do {
                _ = try await localActor.renameItem(item, to: badName)
                XCTFail("Expected renameItem to throw for forbidden name: \(badName)")
            } catch {
                // Expected to fail sanitization
            }
        }
    }
}
#endif
