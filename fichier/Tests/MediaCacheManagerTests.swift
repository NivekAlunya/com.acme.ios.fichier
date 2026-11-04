//
//  MediaCacheManagerTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
import PDFKit
@testable import fichier

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
    
    // MARK: - PDF Thumbnail & Range Data Tests
    
    private func createSamplePDFData() -> Data {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return Data() }
        var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 200)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
        context.beginPage(mediaBox: &mediaBox)
        context.setFillColor(UIColor.red.cgColor)
        context.fill(CGRect(x: 20, y: 20, width: 160, height: 160))
        context.endPage()
        context.closePDF()
        return pdfData as Data
    }
    
    func testPDFThumbnailGenerationFromValidData() {
        let manager = MediaCacheManager.shared
        let pdfData = createSamplePDFData()
        XCTAssertFalse(pdfData.isEmpty)
        
        let thumb = manager.generatePDFThumbnail(from: pdfData, maxDimension: 260)
        XCTAssertNotNil(thumb)
        if let thumb {
            XCTAssertLessThanOrEqual(thumb.size.width, 260)
            XCTAssertLessThanOrEqual(thumb.size.height, 260)
        }
    }
    
    func testPDFThumbnailGenerationFromParsedDocument() {
        let manager = MediaCacheManager.shared
        let pdfData = createSamplePDFData()
        guard let doc = PDFDocument(data: pdfData) else {
            XCTFail("Failed to instantiate PDFDocument from valid sample data")
            return
        }
        
        let thumb = manager.generatePDFThumbnail(from: doc, maxDimension: 260)
        XCTAssertNotNil(thumb)
        if let thumb {
            XCTAssertLessThanOrEqual(thumb.size.width, 260)
            XCTAssertLessThanOrEqual(thumb.size.height, 260)
        }
    }
    
    func testPDFThumbnailGenerationFromCorruptedDataSafelyReturnsNil() {
        let manager = MediaCacheManager.shared
        let corruptedData = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55])
        
        let thumb = manager.generatePDFThumbnail(from: corruptedData, maxDimension: 260)
        XCTAssertNil(thumb, "Corrupted data must safely return nil without crashing")
    }
    
    func testPDFThumbnailCacheInvalidationPurgesFiles() {
        let manager = MediaCacheManager.shared
        let item = MediaItem(
            locationID: "test_loc",
            name: "test_doc.pdf",
            rootName: "share",
            path: "test_doc.pdf",
            isDirectory: false
        )
        
        let (diskKey, _, _) = manager.thumbnailKeys(
            for: item.shareName,
            path: item.path,
            dimension: MediaCacheManager.standardThumbnailDimension,
            connectionID: item.connectionID
        )
        
        let sampleImage = UIImage()
        manager.saveThumbnail(sampleImage, for: diskKey)
        XCTAssertTrue(manager.hasThumbnail(for: diskKey))
        
        manager.invalidateThumbnailCache(for: [item])
        XCTAssertFalse(manager.hasThumbnail(for: diskKey), "Thumbnail file must be deleted after cache invalidation")
    }
}
#endif
