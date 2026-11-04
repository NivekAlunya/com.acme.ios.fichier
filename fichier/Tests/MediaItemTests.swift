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
    
    func testMediaItemEqualityDetectsChildNameMutation() {
        let child1 = MediaItem(
            locationID: "loc_1",
            name: "SubA",
            rootName: "Root",
            path: "/Folder/SubA",
            isDirectory: true
        )
        let child2Mutated = MediaItem(
            locationID: "loc_1",
            name: "SubRenamed",
            rootName: "Root",
            path: "/Folder/SubRenamed",
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
            children: [child2Mutated]
        )
        
        XCTAssertNotEqual(parent1, parent2, "MediaItem equality must detect mutated subfolder names even when item count is identical")
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
    
    func testMediaItemEqualityDoesNotRecurseIntoGrandchildren() {
        let grandchild1 = MediaItem(locationID: "loc_1", name: "Grandchild1", rootName: "Root", path: "/Folder/Sub/G1", isDirectory: true)
        let grandchild2 = MediaItem(locationID: "loc_1", name: "Grandchild2", rootName: "Root", path: "/Folder/Sub/G2", isDirectory: true)
        
        let childA = MediaItem(locationID: "loc_1", name: "Sub", rootName: "Root", path: "/Folder/Sub", isDirectory: true, children: [grandchild1])
        let childB = MediaItem(locationID: "loc_1", name: "Sub", rootName: "Root", path: "/Folder/Sub", isDirectory: true, children: [grandchild2])
        
        let parentA = MediaItem(locationID: "loc_1", name: "Folder", rootName: "Root", path: "/Folder", isDirectory: true, children: [childA])
        let parentB = MediaItem(locationID: "loc_1", name: "Folder", rootName: "Root", path: "/Folder", isDirectory: true, children: [childB])
        
        // Parent items are equal because direct child identity/attributes match, preserving O(K) shallow diffing
        XCTAssertEqual(parentA, parentB)
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
