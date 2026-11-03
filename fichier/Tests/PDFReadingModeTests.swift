//
//  PDFReadingModeTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest

final class PDFReadingModeTests: XCTestCase {
    func testAllCasesCount() {
        XCTAssertEqual(PDFReadingMode.allCases.count, 3)
    }
    
    func testContinuousReadingMode() {
        let mode = PDFReadingMode.continuous
        XCTAssertFalse(mode.isBookMode)
        XCTAssertFalse(mode.displaysAsBook)
        XCTAssertEqual(mode.rawValue, "continuous")
        XCTAssertEqual(mode.id, "continuous")
        XCTAssertEqual(mode.iconName, "doc.text")
    }
    
    func testBookReadingMode() {
        let mode = PDFReadingMode.book
        XCTAssertTrue(mode.isBookMode)
        XCTAssertTrue(mode.displaysAsBook)
        XCTAssertEqual(mode.rawValue, "book")
        XCTAssertEqual(mode.id, "book")
        XCTAssertEqual(mode.iconName, "book")
    }
    
    func testTwoUpReadingMode() {
        let mode = PDFReadingMode.twoUp
        XCTAssertTrue(mode.isBookMode)
        XCTAssertFalse(mode.displaysAsBook)
        XCTAssertEqual(mode.rawValue, "twoUp")
        XCTAssertEqual(mode.id, "twoUp")
        XCTAssertEqual(mode.iconName, "rectangle.split.2x1")
    }
}
#endif
