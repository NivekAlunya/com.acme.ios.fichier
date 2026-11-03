//
//  PDFThumbnailSidebarTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
import PDFKit
import UIKit
@testable import fichier

@MainActor
final class PDFThumbnailSidebarTests: XCTestCase {
    func testThumbnailSidebarInitialization() {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        let data = renderer.pdfData { context in
            context.beginPage()
            context.beginPage()
            context.beginPage()
        }
        guard let doc = PDFDocument(data: data) else {
            XCTFail("Failed to create PDFDocument")
            return
        }
        
        var selectedPage = 0
        let sidebar = PDFLeadingThumbnailSidebarView(
            document: doc,
            currentPage: 1,
            endVisiblePage: 2,
            onPageSelected: { page in
                selectedPage = page
            }
        )
        
        XCTAssertEqual(sidebar.document.pageCount, 3)
        XCTAssertEqual(sidebar.currentPage, 1)
        XCTAssertEqual(sidebar.endVisiblePage, 2)
        
        sidebar.onPageSelected(2)
        XCTAssertEqual(selectedPage, 2)
    }
}
#endif
