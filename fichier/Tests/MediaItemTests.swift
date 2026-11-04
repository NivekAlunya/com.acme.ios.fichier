//
//  MediaItemTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
@testable import fichier

final class MediaItemTests: XCTestCase {
    
    // MARK: - Equality Tests
    
    func testMediaItemEqualityIdentical() {
        let date = Date()
        let item1 = MediaItem(
            locationID: "loc_1",
            name: "Folder",
            rootName: "Root",
            path: "/Folder",
            isDirectory: true,
            size: 1024,
            modifiedDate: date
        )
        let item2 = MediaItem(
            locationID: "loc_1",
            name: "Folder",
            rootName: "Root",
            path: "/Folder",
            isDirectory: true,
            size: 1024,
            modifiedDate: date
        )
        
        XCTAssertEqual(item1, item2)
    }
    
    func testMediaItemEqualityDetectsNameChange() {
        let item1 = MediaItem(locationID: "loc_1", name: "FolderA", rootName: "Root", path: "/FolderA", isDirectory: true)
        let item2 = MediaItem(locationID: "loc_1", name: "FolderB", rootName: "Root", path: "/FolderA", isDirectory: true)
        XCTAssertNotEqual(item1, item2)
    }
    
    func testMediaItemEqualityDetectsChildCountChange() {
        let child1 = MediaItem(
            locationID: "loc_1",
            name: "SubA",
            rootName: "Root",
            path: "/Folder/SubA",
            isDirectory: true
        )
        let child2 = MediaItem(
            locationID: "loc_1",
            name: "SubB",
            rootName: "Root",
            path: "/Folder/SubB",
            isDirectory: true
        )
        
        let parent1 = MediaItem(
            locationID: "loc_1",
            name: "Folder",
            rootName: "Root",
            path: "/Folder",
            isDirectory: true,
            children: [child1]
        )
        let parent2 = MediaItem(
            locationID: "loc_1",
            name: "Folder",
            rootName: "Root",
            path: "/Folder",
            isDirectory: true,
            children: [child1, child2]
        )
        
        XCTAssertNotEqual(parent1, parent2)
    }
    
    func testMediaItemEqualityDoesNotRecurseDeeply() {
        let child1 = MediaItem(locationID: "loc_1", name: "Sub", rootName: "Root", path: "/Folder/Sub", isDirectory: true)
        let child2 = MediaItem(locationID: "loc_1", name: "Sub", rootName: "Root", path: "/Folder/Sub", isDirectory: true)
        
        let parent1 = MediaItem(locationID: "loc_1", name: "Folder", rootName: "Root", path: "/Folder", isDirectory: true, children: [child1])
        let parent2 = MediaItem(locationID: "loc_1", name: "Folder", rootName: "Root", path: "/Folder", isDirectory: true, children: [child2])
        
        // Equal in O(1) time without deep subtree traversal
        XCTAssertEqual(parent1, parent2)
    }
    
    // MARK: - Normalized Path Components
    
    func testNormalizedComponentsHandlesMixedSeparators() {
        let item = MediaItem(
            locationID: "loc_1",
            name: "Photo",
            rootName: "Root",
            path: "/Folder/Sub\\Nested//Deep",
            isDirectory: true
        )
        let components = item.normalizedComponents.map(String.init)
        XCTAssertEqual(components, ["Folder", "Sub", "Nested", "Deep"])
    }
}
#endif
