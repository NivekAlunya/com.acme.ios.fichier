//
//  PDFSpreadTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest

final class PDFSpreadTests: XCTestCase {
    func testBuildSpreadsWithCover() {
        // 5 pages, displaysAsBook = true
        // Spread 0: [0] (Page 1)
        // Spread 1: [1, 2] (Pages 2 & 3)
        // Spread 2: [3, 4] (Pages 4 & 5)
        let spreads = PDFSpread.buildSpreads(pageCount: 5, displaysAsBook: true)
        XCTAssertEqual(spreads.count, 3)
        XCTAssertEqual(spreads[0].pageIndices, [0])
        XCTAssertEqual(spreads[0].firstPageNumber, 1)
        XCTAssertEqual(spreads[0].lastPageNumber, 1)
        XCTAssertEqual(spreads[0].displayText, "Page 1")
        
        XCTAssertEqual(spreads[1].pageIndices, [1, 2])
        XCTAssertEqual(spreads[1].firstPageNumber, 2)
        XCTAssertEqual(spreads[1].lastPageNumber, 3)
        XCTAssertEqual(spreads[1].displayText, "Pages 2–3")
        
        XCTAssertEqual(spreads[2].pageIndices, [3, 4])
        XCTAssertEqual(spreads[2].firstPageNumber, 4)
        XCTAssertEqual(spreads[2].lastPageNumber, 5)
    }
    
    func testBuildSpreadsWithoutCover() {
        // 3 pages, displaysAsBook = false
        // Spread 0: [0, 1] (Pages 1 & 2)
        // Spread 1: [2] (Page 3)
        let spreads = PDFSpread.buildSpreads(pageCount: 3, displaysAsBook: false)
        XCTAssertEqual(spreads.count, 2)
        XCTAssertEqual(spreads[0].pageIndices, [0, 1])
        XCTAssertEqual(spreads[1].pageIndices, [2])
        XCTAssertEqual(spreads[1].displayText, "Page 3")
    }
    
    func testBuildSpreadsSinglePage() {
        let spreads = PDFSpread.buildSpreads(pageCount: 1, displaysAsBook: true)
        XCTAssertEqual(spreads.count, 1)
        XCTAssertEqual(spreads[0].pageIndices, [0])
        XCTAssertEqual(spreads[0].displayText, "Page 1")
    }
    
    func testBuildSpreadsEmpty() {
        let spreads = PDFSpread.buildSpreads(pageCount: 0, displaysAsBook: true)
        XCTAssertTrue(spreads.isEmpty)
    }
}
#endif
