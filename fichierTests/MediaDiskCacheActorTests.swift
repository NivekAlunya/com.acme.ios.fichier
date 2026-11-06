//
//  MediaDiskCacheActorTests.swift
//  fichierTests
//

#if DEBUG && canImport(XCTest)
import XCTest
@testable import fichier

final class MediaDiskCacheActorTests: XCTestCase {
    
    private var testDir: URL!
    private var actor: MediaDiskCacheActor!
    
    override func setUp() async throws {
        try await super.setUp()
        actor = MediaDiskCacheActor()
        let temp = FileManager.default.temporaryDirectory
        testDir = temp.appendingPathComponent("MediaDiskCacheActorTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        if let testDir {
            try? FileManager.default.removeItem(at: testDir)
        }
        actor = nil
        try await super.tearDown()
    }
    
    func testAtomicWriteAndCalculateSize() async throws {
        let fileURL = testDir.appendingPathComponent("test.bin")
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        
        try await actor.writeData(data, to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        
        let size = await actor.calculateTotalSize(in: [testDir])
        XCTAssertEqual(size, 5)
    }
    
    func testFileMigration() async throws {
        let legacyURL = testDir.appendingPathComponent("legacy.dat")
        let destURL = testDir.appendingPathComponent("new.dat")
        let payload = Data("hello migration".utf8)
        
        try payload.write(to: legacyURL)
        await actor.migrateFile(from: legacyURL, to: destURL)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
    }
    
    func testEvictionFifoOrder() async throws {
        let subDir = testDir.appendingPathComponent("evictSub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        
        let oldFile = subDir.appendingPathComponent("old.dat")
        let newFile = subDir.appendingPathComponent("new.dat")
        
        let oldData = Data(count: 1000)
        let newData = Data(count: 1000)
        
        try oldData.write(to: oldFile)
        // Adjust modification date to past
        let pastDate = Date().addingTimeInterval(-100)
        try FileManager.default.setAttributes([.modificationDate: pastDate], ofItemAtPath: oldFile.path)
        
        try newData.write(to: newFile)
        
        // Evict with budget 1500 bytes (total is 2000) -> oldest file must be evicted
        await actor.evictFilesIfNeeded(in: subDir, limitBytes: 1500)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path), "Oldest file must be evicted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.path), "Newer file must be preserved")
    }
    
    func testCleanOrphanedPartFiles() async throws {
        let partFile = testDir.appendingPathComponent("download.part")
        try Data([0xAA, 0xBB]).write(to: partFile)
        
        let past = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: partFile.path)
        
        await actor.cleanOrphanedPartFiles(in: [testDir], olderThan: 3600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partFile.path))
    }
    
    func testClearDirectories() async throws {
        let f1 = testDir.appendingPathComponent("f1.tmp")
        let f2 = testDir.appendingPathComponent("f2.tmp")
        try Data([0x01]).write(to: f1)
        try Data([0x02]).write(to: f2)
        
        await actor.clearDirectories([testDir], protectedURLs: [f1])
        XCTAssertTrue(FileManager.default.fileExists(atPath: f1.path), "Protected URL must remain")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f2.path), "Unprotected URL must be removed")
    }
}
#endif
