//
//  MediaCacheManagerTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest

final class MediaCacheManagerTests: XCTestCase {
    func testDocumentsDirectoryInitialization() {
        let manager = MediaCacheManager.shared
        _ = manager
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let docsDir = caches.appendingPathComponent("SMBDocuments", isDirectory: true)
        
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: docsDir.path, isDirectory: &isDir)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDir.boolValue)
    }
    
    func testLocalDocumentURLSanitization() {
        let manager = MediaCacheManager.shared
        let maliciousItem = MediaItem(
            locationID: "conn_123",
            name: "malicious.pdf",
            rootName: "share",
            path: "../../../../etc/passwd.pdf",
            isDirectory: false
        )
        
        let url = manager.localDocumentURL(for: maliciousItem)
        XCTAssertFalse(url.path.contains(".."))
        XCTAssertTrue(url.path.contains("SMBDocuments"))
        XCTAssertEqual(url.pathExtension, "pdf")
        
        let sameItem = MediaItem(
            locationID: "conn_123",
            name: "malicious.pdf",
            rootName: "share",
            path: "../../../../etc/passwd.pdf",
            isDirectory: false
        )
        XCTAssertEqual(url, manager.localDocumentURL(for: sameItem))
    }
}
#endif
