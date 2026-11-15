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
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdFolder.localURL!.path))
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
}
#endif
