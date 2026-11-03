//
//  PDFKitCoordinatorTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
import PDFKit
import UIKit

@MainActor
final class PDFKitCoordinatorTests: XCTestCase {
    func testCoordinatorInitialization() {
        var pageChangedCalled = false
        var tapCalled = false
        
        let coordinator = PDFKitCoordinator(
            onPageChange: { _, _ in pageChangedCalled = true },
            onTap: { tapCalled = true }
        )
        
        XCTAssertNotNil(coordinator)
        coordinator.handleSingleTap()
        XCTAssertTrue(tapCalled)
        XCTAssertFalse(pageChangedCalled)
    }
    
    func testAttachAndPageChange() {
        var currentPage = 0
        var totalPages = 0
        
        let coordinator = PDFKitCoordinator(
            onPageChange: { current, total in
                currentPage = current
                totalPages = total
            }
        )
        
        let pdfView = PDFView()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        let data = renderer.pdfData { context in
            context.beginPage()
            context.beginPage()
        }
        let doc = PDFDocument(data: data)
        pdfView.document = doc
        
        coordinator.attach(to: pdfView)
        
        XCTAssertEqual(totalPages, 2)
        XCTAssertEqual(currentPage, 1)
        
        coordinator.detach()
        XCTAssertNil(coordinator.pdfView)
    }
}
#endif
