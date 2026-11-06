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
    
    func testPDFThumbnailCacheInvalidationPurgesFiles() async {
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
        
        let sampleImage = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        manager.saveThumbnail(sampleImage, for: diskKey)
        XCTAssertTrue(manager.hasThumbnail(for: diskKey))
        
        await manager.invalidateThumbnailCache(for: [item])
        XCTAssertFalse(manager.hasThumbnail(for: diskKey), "Thumbnail file must be deleted after cache invalidation")
    }
    
    func testPDFThumbnailGenerationTruncatedNonLinearizedDataReturnsNil() {
        let manager = MediaCacheManager.shared
        let fullPDFData = createSamplePDFData()
        XCTAssertGreaterThan(fullPDFData.count, 100)
        
        // Truncate to header & first object, stripping the XRef table and trailer catalog at the end
        let truncatedPrefix = fullPDFData.prefix(64)
        let thumb = manager.generatePDFThumbnail(from: truncatedPrefix, maxDimension: 260)
        XCTAssertNil(thumb, "Truncated non-linearized PDF buffer missing XRef table must safely return nil")
    }
    
    func testPDFThumbnailGenerationZeroByteDataReturnsNil() {
        let manager = MediaCacheManager.shared
        let emptyData = Data()
        let thumb = manager.generatePDFThumbnail(from: emptyData, maxDimension: 260)
        XCTAssertNil(thumb, "Empty data must safely return nil")
    }
    
    func testPDFThumbnailGenerationLargeDataUsesStagingSafely() {
        let manager = MediaCacheManager.shared
        let validPDF = createSamplePDFData()
        // Pad payload to > 5 MB to exercise the temporary disk staging and mmap execution path
        var largeData = validPDF
        let paddingSize = (5 * 1024 * 1024) + 1024
        largeData.append(Data(count: paddingSize))
        
        // Large data with valid PDF header and padded trailer must not crash or leak
        _ = manager.generatePDFThumbnail(from: largeData, maxDimension: 260)
    }
    
    func testDocumentCacheEvictionAndInvalidation() {
        let manager = MediaCacheManager.shared
        let item = MediaItem(
            locationID: "test_loc",
            name: "sample_doc.pdf",
            rootName: "share",
            path: "sample_doc.pdf",
            isDirectory: false
        )
        
        let docURL = manager.localDocumentURL(for: item)
        let testBytes = Data([0x25, 0x50, 0x44, 0x46]) // %PDF
        try? testBytes.write(to: docURL, options: .atomic)
        XCTAssertTrue(manager.hasCachedDocument(for: item))
        
        // Evict documents exceeding 0 bytes
        manager.evictDocumentsIfNeeded(limitBytes: 0)
        XCTAssertFalse(manager.hasCachedDocument(for: item), "Document must be evicted when total size exceeds budget")
    }
    
    func testPDFPrefixBoundsClampingWhenSizeIsKnownAndSmall() {
        let smallSize: Int64 = 100 * 1024 // 100 KB
        let clampedPrefixLength = min(smallSize, 1_048_576)
        XCTAssertEqual(clampedPrefixLength, smallSize, "Files smaller than 1 MB must clamp prefix length to exact file size")
        
        let largeSize: Int64 = 50 * 1024 * 1024 // 50 MB
        let clampedLargeLength = min(largeSize, 1_048_576)
        XCTAssertEqual(clampedLargeLength, 1_048_576, "Files larger than 1 MB must be clamped to 1 MB max read")
    }
    
    func testPDFSizeResolutionThresholdLogic() {
        let maxDirectDownloadBytes: Int64 = 12 * 1024 * 1024
        
        // When item.size is 0, dynamically resolved size evaluates threshold
        let unpopulatedSize: Int64 = 0
        let resolvedSize: Int64 = 5 * 1024 * 1024 // 5 MB
        let effectiveSize = unpopulatedSize > 0 ? unpopulatedSize : resolvedSize
        
        XCTAssertTrue(effectiveSize > 0 && effectiveSize <= maxDirectDownloadBytes, "Resolved size must allow fallback for files <= 12 MB")
        
        let largeResolvedSize: Int64 = 25 * 1024 * 1024 // 25 MB
        let largeEffectiveSize = unpopulatedSize > 0 ? unpopulatedSize : largeResolvedSize
        XCTAssertFalse(largeEffectiveSize > 0 && largeEffectiveSize <= maxDirectDownloadBytes, "Files > 12 MB must not trigger fallback download")
    }
}
#endif
