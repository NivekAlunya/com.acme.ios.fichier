//
//  PDFPlaylistNavigationTests.swift
//  fichier
//

#if !os(tvOS) && DEBUG && canImport(XCTest)
import XCTest
@testable import Fichier

@MainActor
final class PDFPlaylistNavigationTests: XCTestCase {
    
    private func createTestMediaItem(name: String) -> MediaItem {
        MediaItem(
            locationID: "loc_pdf_test",
            name: name,
            rootName: "documents",
            path: "documents/\(name)",
            isDirectory: false
        )
    }
    
    func testSingleDocumentPlaylistInitialization() {
        let manager = StorageLocationManager()
        let doc1 = createTestMediaItem(name: "doc1.pdf")
        
        let viewModel = PDFDetailViewModel(
            manager: manager,
            documents: [doc1],
            initialItem: doc1
        )
        
        XCTAssertEqual(viewModel.documents.count, 1)
        XCTAssertEqual(viewModel.documents.first?.id, doc1.id)
    }
    
    func testMultipleDocumentsPlaylistFiltersPDFsOnly() {
        let manager = StorageLocationManager()
        let doc1 = createTestMediaItem(name: "report.pdf")
        let image = createTestMediaItem(name: "photo.jpg")
        let doc2 = createTestMediaItem(name: "guide.pdf")
        
        let viewModel = PDFDetailViewModel(
            manager: manager,
            documents: [doc1, image, doc2],
            initialItem: doc1
        )
        
        XCTAssertEqual(viewModel.documents.count, 2)
        XCTAssertEqual(viewModel.documents.map(\.name), ["report.pdf", "guide.pdf"])
    }
    
    func testContextContainsTargetPDFResolvesFilteredSublist() {
        let doc1 = createTestMediaItem(name: "invoice_2025.pdf")
        let doc2 = createTestMediaItem(name: "invoice_2026.pdf")
        let doc3 = createTestMediaItem(name: "guide.pdf")
        let folderPictures = [doc1, doc2, doc3]
        
        // Simulating search filter "invoice"
        let filteredContext = [doc1, doc2]
        
        let source = filteredContext.contains(where: { $0.id == doc1.id }) ? filteredContext : folderPictures
        let manager = StorageLocationManager()
        let viewModel = PDFDetailViewModel(manager: manager, documents: source, initialItem: doc1)
        XCTAssertEqual(viewModel.documents.count, 2)
        XCTAssertEqual(viewModel.documents.map(\.name), ["invoice_2025.pdf", "invoice_2026.pdf"])
    }
    
    func testContextEmptyOrMissingTargetPDFResolvesAllFolderPDFs() {
        let doc1 = createTestMediaItem(name: "file1.pdf")
        let doc2 = createTestMediaItem(name: "file2.pdf")
        let doc3 = createTestMediaItem(name: "file3.pdf")
        let photo = createTestMediaItem(name: "image.png")
        let folderPictures = [doc1, doc2, doc3, photo]
        
        // Simulating empty or stale context
        let emptyContext: [MediaItem] = []
        
        let source = emptyContext.contains(where: { $0.id == doc1.id }) ? emptyContext : folderPictures
        let manager = StorageLocationManager()
        let viewModel = PDFDetailViewModel(manager: manager, documents: source, initialItem: doc1)
        XCTAssertEqual(viewModel.documents.count, 3)
        XCTAssertEqual(viewModel.documents.map(\.name), ["file1.pdf", "file2.pdf", "file3.pdf"])
    }
}
#endif
