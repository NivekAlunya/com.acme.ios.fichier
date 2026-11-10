//
//  SMBStreamingServerRangeTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
import FichierKit
@testable import fichier

final class SMBStreamingServerRangeTests: XCTestCase {
    func testValidBoundedRange() {
        let parsed = HTTPRangeParser.parse("Range: bytes=0-1024", totalSize: 2048)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.start, 0)
        XCTAssertEqual(parsed?.end, 1024)
    }
    
    func testValidOpenEndedRange() {
        let parsed = HTTPRangeParser.parse("Range: bytes=1024-", totalSize: 2048)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.start, 1024)
        XCTAssertEqual(parsed?.end, 2047)
    }
    
    func testValidSuffixRange() {
        let parsed = HTTPRangeParser.parse("Range: bytes=-500", totalSize: 2048)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.start, 1548)
        XCTAssertEqual(parsed?.end, 2047)
    }
    
    func testSuffixRangeExceedingTotalSizeClampsToZero() {
        let parsed = HTTPRangeParser.parse("Range: bytes=-5000", totalSize: 2048)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.start, 0)
        XCTAssertEqual(parsed?.end, 2047)
    }
    
    func testRangeEndBeyondTotalSizeClamped() {
        let parsed = HTTPRangeParser.parse("Range: bytes=1000-5000", totalSize: 2048)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.start, 1000)
        XCTAssertEqual(parsed?.end, 2047)
    }
    
    func testStartExceedingOrEqualTotalSizeReturnsNil() {
        let parsedAtSize = HTTPRangeParser.parse("Range: bytes=2048-", totalSize: 2048)
        XCTAssertNil(parsedAtSize, "Start equal to totalSize must be unsatisfiable")
        
        let parsedBeyond = HTTPRangeParser.parse("Range: bytes=3000-4000", totalSize: 2048)
        XCTAssertNil(parsedBeyond, "Start beyond totalSize must be unsatisfiable")
    }
    
    func testEndLessThanStartReturnsNil() {
        let parsed = HTTPRangeParser.parse("Range: bytes=500-200", totalSize: 2048)
        XCTAssertNil(parsed, "End before start must be unsatisfiable")
    }
    
    func testZeroSuffixReturnsNil() {
        let parsed = HTTPRangeParser.parse("Range: bytes=-0", totalSize: 2048)
        XCTAssertNil(parsed, "Zero length suffix must be unsatisfiable")
    }
    
    func testZeroOrNegativeTotalSizeReturnsNil() {
        let parsed = HTTPRangeParser.parse("Range: bytes=0-100", totalSize: 0)
        XCTAssertNil(parsed, "Range on empty file must be unsatisfiable")
    }
    
    func testMalformedOrNonByteUnitsReturnNil() {
        let nonByteUnit = HTTPRangeParser.parse("Range: items=0-100", totalSize: 2048)
        XCTAssertNil(nonByteUnit, "Non-byte units must be rejected")
        
        let missingEquals = HTTPRangeParser.parse("Range: bytes 0-100", totalSize: 2048)
        XCTAssertNil(missingEquals, "Missing '=' must be rejected")
        
        let multiRange = HTTPRangeParser.parse("Range: bytes=0-10, 20-30", totalSize: 2048)
        XCTAssertNil(multiRange, "Multipart ranges must be rejected")
    }
}
#endif
