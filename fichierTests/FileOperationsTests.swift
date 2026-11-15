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
}
#endif
