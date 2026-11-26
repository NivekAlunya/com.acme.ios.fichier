//
//  DownloadProgressFormattingTests.swift
//  fichierTests
//

#if DEBUG && canImport(XCTest)
import XCTest
import Foundation
@testable import Fichier

@MainActor
final class DownloadProgressFormattingTests: XCTestCase {

    func testLocalizedPercentageFormattingAcrossLocales() {
        let fraction = 0.42
        let testLocales = [
            "en_US",     // English (LTR)
            "fr_FR",     // French (LTR, space before percent)
            "de_DE",     // German (LTR, space before percent)
            "zh_Hans_CN", // Chinese Simplified
            "ar_SA"      // Arabic (RTL, localized digits/symbol)
        ]

        for identifier in testLocales {
            let locale = Locale(identifier: identifier)
            let formatted = fraction.formatted(.percent.precision(.fractionLength(0)).locale(locale))

            XCTAssertFalse(formatted.isEmpty, "Formatted percentage should not be empty for locale \(identifier)")
            XCTAssertTrue(
                formatted.contains("42") || formatted.contains("٤٢"),
                "Formatted percentage should contain localized representation of 42 for locale \(identifier), got: \(formatted)"
            )
        }
    }

    func testProgressStringInterpolation() {
        let bytes: Int64 = 42_000_000
        let totalBytes: Int64 = 100_000_000

        let readStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let totalStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        let percent = (Double(bytes) / Double(totalBytes)).formatted(.percent.precision(.fractionLength(0)))

        let singleItemMessage = String(
            localized: .Strings.galleryDownloadProgressBytes(readStr, totalStr, percent)
        )
        XCTAssertTrue(singleItemMessage.contains(readStr), "Message should contain read byte count")
        XCTAssertTrue(singleItemMessage.contains(totalStr), "Message should contain total byte count")
        XCTAssertTrue(singleItemMessage.contains(percent), "Message should contain pre-formatted percentage string")

        let batchItemMessage = String(
            localized: .Strings.galleryDownloadBatchItemDetail(1, 3, "video.mov", readStr, totalStr, percent)
        )
        XCTAssertTrue(batchItemMessage.contains("1"), "Batch message should contain current index")
        XCTAssertTrue(batchItemMessage.contains("3"), "Batch message should contain total item count")
        XCTAssertTrue(batchItemMessage.contains("video.mov"), "Batch message should contain item name")
        XCTAssertTrue(batchItemMessage.contains(readStr), "Batch message should contain read byte count")
        XCTAssertTrue(batchItemMessage.contains(percent), "Batch message should contain pre-formatted percentage string")
    }

    func testZeroAndFullCompletionPercentages() {
        let zeroPercent = (0.0).formatted(.percent.precision(.fractionLength(0)))
        let fullPercent = (1.0).formatted(.percent.precision(.fractionLength(0)))

        let zeroMessage = String(
            localized: .Strings.galleryDownloadProgressBytes("0 KB", "10 MB", zeroPercent)
        )
        let fullMessage = String(
            localized: .Strings.galleryDownloadProgressBytes("10 MB", "10 MB", fullPercent)
        )

        XCTAssertTrue(zeroMessage.contains(zeroPercent))
        XCTAssertTrue(fullMessage.contains(fullPercent))
    }
}
#endif
