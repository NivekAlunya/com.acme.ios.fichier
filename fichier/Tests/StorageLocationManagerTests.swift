//
//  StorageLocationManagerTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
@testable import fichier

@MainActor
final class StorageLocationManagerTests: XCTestCase {
    
    // MARK: - Root Folder Detection
    
    func testRootFolderDetectionForSMB() {
        let manager = StorageLocationManager()
        
        let rootSlash = MediaItem(
            locationID: "smb_1",
            name: "Share",
            rootName: "Share",
            path: "/",
            isDirectory: true
        )
        let rootEmpty = MediaItem(
            locationID: "smb_1",
            name: "Share",
            rootName: "Share",
            path: "",
            isDirectory: true
        )
        let subfolder = MediaItem(
            locationID: "smb_1",
            name: "Vacation",
            rootName: "Share",
            path: "/Vacation",
            isDirectory: true
        )
        
        XCTAssertTrue(manager.isRootFolder(rootSlash))
        XCTAssertTrue(manager.isRootFolder(rootEmpty))
        XCTAssertFalse(manager.isRootFolder(subfolder))
    }
    
    func testRootFolderDetectionForLocalAndPhotos() {
        let manager = StorageLocationManager()
        
        let localURL = URL(fileURLWithPath: "/var/mobile/Containers/Data/Folder")
        let localRoot = MediaItem(
            locationID: "local_1",
            name: "Folder",
            rootName: "Folder",
            path: "",
            isDirectory: true,
            localURL: localURL
        )
        let localSub = MediaItem(
            locationID: "local_1",
            name: "Sub",
            rootName: "Folder",
            path: "Sub",
            isDirectory: true,
            localURL: localURL.appendingPathComponent("Sub")
        )
        let photosRoot = MediaItem(
            locationID: StorageLocation.photosLocationID,
            name: "Photos",
            rootName: "Photos",
            path: "",
            isDirectory: true
        )
        let photosAlbum = MediaItem(
            locationID: StorageLocation.photosLocationID,
            name: "Album",
            rootName: "Photos",
            path: "album_id_123",
            isDirectory: true
        )
        
        XCTAssertTrue(manager.isRootFolder(localRoot))
        XCTAssertFalse(manager.isRootFolder(localSub))
        XCTAssertTrue(manager.isRootFolder(photosRoot))
        XCTAssertFalse(manager.isRootFolder(photosAlbum))
    }
    
    // MARK: - Path Hygiene & Parent Derivation
    
    func testDeriveParentFolderForSMBPaths() {
        let manager = StorageLocationManager()
        
        let deepItem = MediaItem(
            locationID: "smb_1",
            name: "Level3",
            rootName: "Share",
            path: "/Level1/Level2/Level3",
            isDirectory: true
        )
        let parent = manager.deriveParentFolder(for: deepItem)
        XCTAssertNotNil(parent)
        XCTAssertEqual(parent?.name, "Level2")
        XCTAssertEqual(parent?.path, "/Level1/Level2")
        
        let midItem = MediaItem(
            locationID: "smb_1",
            name: "Level1",
            rootName: "Share",
            path: "/Level1",
            isDirectory: true
        )
        let rootParent = manager.deriveParentFolder(for: midItem)
        XCTAssertNotNil(rootParent)
        XCTAssertEqual(rootParent?.name, "Share")
        XCTAssertEqual(rootParent?.path, "/")
    }
    
    func testDeriveParentFolderSanitizesBackslashesAndTraversal() {
        let manager = StorageLocationManager()
        
        // Windows-style backslashes and redundant separators
        let windowsItem = MediaItem(
            locationID: "smb_1",
            name: "SubFolder",
            rootName: "Share",
            path: "Folder\\SubFolder",
            isDirectory: true
        )
        let parent = manager.deriveParentFolder(for: windowsItem)
        XCTAssertNotNil(parent)
        XCTAssertEqual(parent?.name, "Share")
        XCTAssertEqual(parent?.path, "/")
        
        // Path with traversal components ignored
        let traversalItem = MediaItem(
            locationID: "smb_1",
            name: "Target",
            rootName: "Share",
            path: "/Folder/./../Folder/Target",
            isDirectory: true
        )
        let safeParent = manager.deriveParentFolder(for: traversalItem)
        XCTAssertNotNil(safeParent)
        XCTAssertEqual(safeParent?.path, "/Folder/Folder")
    }
    
    // MARK: - Cached Parent Folder Lookup
    
    func testCachedParentFolderUpdatesOnSelectedFolderChange() {
        let manager = StorageLocationManager()
        
        let root = MediaItem(
            locationID: "smb_1",
            name: "Share",
            rootName: "Share",
            path: "/",
            isDirectory: true
        )
        let sub = MediaItem(
            locationID: "smb_1",
            name: "Photos",
            rootName: "Share",
            path: "/Photos",
            isDirectory: true
        )
        
        manager.folderTree = [root]
        manager.selectedFolder = root
        XCTAssertNil(manager.parentFolder, "Root folder must not have a parent folder")
        
        manager.selectedFolder = sub
        XCTAssertNotNil(manager.parentFolder, "Subfolder must resolve parent folder")
        XCTAssertEqual(manager.parentFolder?.name, "Share")
    }
}
#endif
