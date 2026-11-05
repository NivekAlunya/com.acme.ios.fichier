//
//  VideoFormatStyleTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
import SwiftUI
@testable import fichier

@MainActor
final class VideoFormatStyleTests: XCTestCase {
    
    func testFormatLabels() {
        XCTAssertEqual(VideoFormatStyle.label(for: "mkv"), "MKV")
        XCTAssertEqual(VideoFormatStyle.label(for: "mp4"), "MP4")
        XCTAssertEqual(VideoFormatStyle.label(for: "avi"), "AVI")
        XCTAssertEqual(VideoFormatStyle.label(for: "webm"), "WEBM")
        XCTAssertEqual(VideoFormatStyle.label(for: ".mov"), "MOV")
        XCTAssertEqual(VideoFormatStyle.label(for: ""), "VIDEO")
    }
    
    func testDistinctColorsPerFormat() {
        let mkvColor = VideoFormatStyle.color(for: "mkv")
        let mp4Color = VideoFormatStyle.color(for: "mp4")
        let aviColor = VideoFormatStyle.color(for: "avi")
        let webmColor = VideoFormatStyle.color(for: "webm")
        let movColor = VideoFormatStyle.color(for: "mov")
        let flvColor = VideoFormatStyle.color(for: "flv")
        
        // Assert colors are returned and distinguishable
        XCTAssertEqual(mp4Color, Color.blue)
        XCTAssertEqual(movColor, Color.cyan)
        XCTAssertEqual(aviColor, Color.orange)
        XCTAssertNotEqual(mkvColor, mp4Color)
        XCTAssertNotEqual(aviColor, webmColor)
        XCTAssertNotEqual(flvColor, mkvColor)
    }
}
#endif
