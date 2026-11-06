//
//  StorageLocationPersistenceStoreTests.swift
//  fichierTests
//

#if DEBUG && canImport(XCTest)
import XCTest
@testable import fichier

@MainActor
final class StorageLocationPersistenceStoreTests: XCTestCase {
    
    private var testDefaults: UserDefaults!
    private var store: StorageLocationPersistenceStore!
    private let suiteName = "com.acme.ios.fichier.tests.persistence"
    
    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)
        testDefaults.removePersistentDomain(forName: suiteName)
        store = StorageLocationPersistenceStore(userDefaults: testDefaults)
    }
    
    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        store = nil
        super.tearDown()
    }
    
    // MARK: - SMB Connections Tests
    
    func testLoadSavedConnectionsEmptyDefaults() {
        let connections = store.loadSavedConnections()
        XCTAssertTrue(connections.isEmpty)
    }
    
    func testSaveAndRetrieveSMBConnection() {
        let initialConnections: [SavedSMBConnection] = []
        let updated = store.saveValidatedConnection(
            host: "192.168.1.100",
            user: "kevin",
            pass: "secret123",
            hostname: "MacMini",
            existingConnections: initialConnections
        )
        
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].host, "192.168.1.100")
        XCTAssertEqual(updated[0].username, "kevin")
        XCTAssertEqual(updated[0].hostname, "MacMini")
        
        let loaded = store.loadSavedConnections()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, "kevin@192.168.1.100")
        
        let pass = store.password(for: loaded[0])
        XCTAssertEqual(pass, "secret123")
        
        // Remove connection
        let cleaned = store.removeSavedConnection(loaded[0], from: loaded)
        XCTAssertTrue(cleaned.isEmpty)
        XCTAssertTrue(store.loadSavedConnections().isEmpty)
    }
    
    func testCorruptedConnectionsDataReturnsEmpty() {
        testDefaults.set(Data([0xFF, 0xFE, 0xFD]), forKey: "SavedSMBServerConnections_v2")
        let connections = store.loadSavedConnections()
        XCTAssertTrue(connections.isEmpty)
    }
    
    // MARK: - Folder Locations Tests
    
    func testLoadSavedFolderLocationsEmptyDefaults() {
        let locations = store.loadSavedFolderLocations()
        XCTAssertTrue(locations.isEmpty)
    }
    
    func testAddAndRemoveFolderLocation() {
        let location = SavedFolderLocation(
            id: "folder_1",
            name: "Downloads",
            bookmarkData: Data([0x01, 0x02, 0x03]),
            isICloud: false
        )
        
        let updated = store.addSavedFolderLocation(location, into: [])
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].id, "folder_1")
        XCTAssertEqual(updated[0].name, "Downloads")
        
        let loaded = store.loadSavedFolderLocations()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, "folder_1")
        
        // Update bookmark
        let newBookmark = Data([0x04, 0x05, 0x06])
        let afterUpdate = store.updateBookmarkData(newBookmark, for: location, in: loaded)
        XCTAssertEqual(afterUpdate[0].bookmarkData, newBookmark)
        
        // Remove folder location
        let cleaned = store.removeSavedFolderLocation(location, from: afterUpdate)
        XCTAssertTrue(cleaned.isEmpty)
        XCTAssertTrue(store.loadSavedFolderLocations().isEmpty)
    }
    
    func testCorruptedFolderLocationsDataReturnsEmpty() {
        testDefaults.set(Data([0x12, 0x34, 0x56]), forKey: "SavedFolderLocations_v1")
        let locations = store.loadSavedFolderLocations()
        XCTAssertTrue(locations.isEmpty)
    }
}
#endif
