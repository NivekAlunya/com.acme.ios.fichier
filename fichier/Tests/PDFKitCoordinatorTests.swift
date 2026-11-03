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
        coordinator.updatePageInfo()
        
        XCTAssertEqual(totalPages, 2)
        XCTAssertEqual(currentPage, 1)
        
        coordinator.detach()
        XCTAssertNil(coordinator.pdfView)
    }
    
    func testPageRangeChangeCallback() {
        var rangeFirst = 0
        var rangeLast = 0
        var rangeTotal = 0
        
        let coordinator = PDFKitCoordinator(
            onPageRangeChange: { first, last, total in
                rangeFirst = first
                rangeLast = last
                rangeTotal = total
            }
        )
        
        let pdfView = PDFView()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        let data = renderer.pdfData { context in
            context.beginPage()
            context.beginPage()
            context.beginPage()
        }
        let doc = PDFDocument(data: data)
        pdfView.document = doc
        
        coordinator.attach(to: pdfView)
        coordinator.updatePageInfo()
        
        XCTAssertEqual(rangeTotal, 3)
        XCTAssertGreaterThanOrEqual(rangeFirst, 1)
        XCTAssertGreaterThanOrEqual(rangeLast, rangeFirst)
        
        coordinator.detach()
    }
    
    func testNavigationMethods() {
        let coordinator = PDFKitCoordinator(isBookMode: true)
        let pdfView = PDFView()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        let data = renderer.pdfData { context in
            context.beginPage()
            context.beginPage()
            context.beginPage()
        }
        let doc = PDFDocument(data: data)
        pdfView.document = doc
        coordinator.attach(to: pdfView)
        
        coordinator.goToPage(index: 1)
        XCTAssertNotNil(coordinator.pdfView)
        
        coordinator.goToNext()
        coordinator.goToPrevious()
        
        coordinator.updateScrollState()
        
        let pan = UIPanGestureRecognizer()
        coordinator.handlePanGesture(pan)
        
        coordinator.detach()
    }
}
#endif
