//
//  SupportedMediaTypesTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest

final class SupportedMediaTypesTests: XCTestCase {
    func testPDFTypeSupport() {
        XCTAssertTrue(SupportedMediaTypes.isPDF(extension: "pdf"))
        XCTAssertTrue(SupportedMediaTypes.isPDF(extension: "PDF"))
        XCTAssertTrue(SupportedMediaTypes.isDocument(extension: "pdf"))
        XCTAssertFalse(SupportedMediaTypes.isPDF(extension: "png"))
        XCTAssertFalse(SupportedMediaTypes.isDocument(extension: "jpg"))
        XCTAssertTrue(SupportedMediaTypes.allExtensions.contains("pdf"))
    }
}
#endif
