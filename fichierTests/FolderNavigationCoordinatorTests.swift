//
//  FolderNavigationCoordinatorTests.swift
//  fichierTests
//

#if DEBUG && canImport(XCTest)
import XCTest
@testable import fichier

@MainActor
final class FolderNavigationCoordinatorTests: XCTestCase {
    
    private var coordinator: FolderNavigationCoordinator!
    
    override func setUp() {
        super.setUp()
        coordinator = FolderNavigationCoordinator()
    }
    
    override func tearDown() {
        coordinator = nil
        super.tearDown()
    }
    
    // MARK: - Root Folder Detection
    
    func testRootFolderDetectionForSMB() {
        let rootSlash = MediaItem(locationID: "smb_1", name: "Share", rootName: "Share", path: "/", isDirectory: true)
        let rootEmpty = MediaItem(locationID: "smb_1", name: "Share", rootName: "Share", path: "", isDirectory: true)
        let subfolder = MediaItem(locationID: "smb_1", name: "Vacation", rootName: "Share", path: "/Vacation", isDirectory: true)
        
        XCTAssertTrue(coordinator.isRootFolder(rootSlash))
        XCTAssertTrue(coordinator.isRootFolder(rootEmpty))
        XCTAssertFalse(coordinator.isRootFolder(subfolder))
    }
    
    func testRootFolderDetectionForLocalAndPhotos() {
        let localURL = URL(fileURLWithPath: "/tmp/Local")
        let localRoot = MediaItem(locationID: "loc_1", name: "Local", rootName: "Local", path: "", isDirectory: true, localURL: localURL)
        let localSub = MediaItem(locationID: "loc_1", name: "Sub", rootName: "Local", path: "Sub", isDirectory: true, localURL: localURL.appendingPathComponent("Sub"))
        let photosRoot = MediaItem(locationID: StorageLocation.photosLocationID, name: "Photos", rootName: "Photos", path: "", isDirectory: true)
        let photosAlbum = MediaItem(locationID: StorageLocation.photosLocationID, name: "Album", rootName: "Photos", path: "album_1", isDirectory: true)
        
        XCTAssertTrue(coordinator.isRootFolder(localRoot))
        XCTAssertFalse(coordinator.isRootFolder(localSub))
        XCTAssertTrue(coordinator.isRootFolder(photosRoot))
        XCTAssertFalse(coordinator.isRootFolder(photosAlbum))
    }
    
    // MARK: - Parent Resolution and Tree Search
    
    func testParentResolutionFromTree() {
        var parent = MediaItem(locationID: "smb_1", name: "Parent", rootName: "Share", path: "/Parent", isDirectory: true)
        let child = MediaItem(locationID: "smb_1", name: "Child", rootName: "Share", path: "/Parent/Child", isDirectory: true)
        parent.children = [child]
        
        let found = coordinator.findParentInTree(for: child, in: [parent])
        XCTAssertEqual(found?.id, parent.id)
        
        let resolved = coordinator.resolveParentFolder(for: child, in: [parent])
        XCTAssertEqual(resolved?.id, parent.id)
    }
    
    func testDeriveParentFolderForSMBPaths() {
        let deep = MediaItem(locationID: "smb_1", name: "Deep", rootName: "Share", path: "/A/B/Deep", isDirectory: true)
        let parent = coordinator.deriveParentFolder(for: deep)
        XCTAssertEqual(parent?.path, "/A/B")
        XCTAssertEqual(parent?.name, "B")
        
        let single = MediaItem(locationID: "smb_1", name: "Single", rootName: "Share", path: "/Single", isDirectory: true)
        let singleParent = coordinator.deriveParentFolder(for: single)
        XCTAssertEqual(singleParent?.path, "/")
        XCTAssertEqual(singleParent?.name, "Share")
    }
    
    func testDeriveParentFolderForWindowsBackslashesAndTraversal() {
        let winPath = MediaItem(locationID: "smb_1", name: "SubFolder", rootName: "Share", path: "Folder\\SubFolder", isDirectory: true)
        let parent = coordinator.deriveParentFolder(for: winPath)
        XCTAssertEqual(parent?.path, "/Folder")
        XCTAssertEqual(parent?.name, "Folder")
        
        let traversalItem = MediaItem(locationID: "smb_1", name: "Target", rootName: "Share", path: "/Folder/./../Folder/Target", isDirectory: true)
        let safeParent = coordinator.deriveParentFolder(for: traversalItem)
        XCTAssertEqual(safeParent?.path, "/Folder/Folder")
    }
}
#endif
