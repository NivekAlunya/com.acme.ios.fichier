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
        XCTAssertEqual(VideoFormatStyle.label(for: ".mkv"), "MKV")
        XCTAssertEqual(VideoFormatStyle.label(for: "flv"), "FLV")
        XCTAssertEqual(VideoFormatStyle.label(for: "wmv"), "WMV")
        XCTAssertEqual(VideoFormatStyle.label(for: ""), "VIDEO")
        XCTAssertEqual(VideoFormatStyle.label(for: "..."), "VIDEO")
    }
    
    func testContainerColorMapping() {
        let purple = Color(red: 0.58, green: 0.28, blue: 0.88)
        let emeraldGreen = Color(red: 0.16, green: 0.68, blue: 0.38)
        let coralRed = Color(red: 0.90, green: 0.25, blue: 0.25)
        let warmAmber = Color(red: 0.94, green: 0.62, blue: 0.12)
        let seaGreen = Color(red: 0.20, green: 0.70, blue: 0.50)
        let fallback = Color(white: 0.30)
        
        // Exact container mappings
        XCTAssertEqual(VideoFormatStyle.color(for: "mkv"), purple)
        XCTAssertEqual(VideoFormatStyle.color(for: ".mkv"), purple)
        XCTAssertEqual(VideoFormatStyle.color(for: "MKV"), purple)
        
        XCTAssertEqual(VideoFormatStyle.color(for: "mp4"), Color.blue)
        XCTAssertEqual(VideoFormatStyle.color(for: ".mp4"), Color.blue)
        XCTAssertEqual(VideoFormatStyle.color(for: "MP4"), Color.blue)
        
        XCTAssertEqual(VideoFormatStyle.color(for: "mov"), Color.cyan)
        XCTAssertEqual(VideoFormatStyle.color(for: "m4v"), Color.indigo)
        XCTAssertEqual(VideoFormatStyle.color(for: "avi"), Color.orange)
        XCTAssertEqual(VideoFormatStyle.color(for: "webm"), emeraldGreen)
        XCTAssertEqual(VideoFormatStyle.color(for: "flv"), coralRed)
        XCTAssertEqual(VideoFormatStyle.color(for: "f4v"), coralRed)
        XCTAssertEqual(VideoFormatStyle.color(for: "wmv"), warmAmber)
        XCTAssertEqual(VideoFormatStyle.color(for: "asf"), warmAmber)
        XCTAssertEqual(VideoFormatStyle.color(for: "ts"), Color.mint)
        XCTAssertEqual(VideoFormatStyle.color(for: "m2ts"), Color.mint)
        XCTAssertEqual(VideoFormatStyle.color(for: "mts"), Color.mint)
        XCTAssertEqual(VideoFormatStyle.color(for: "ogv"), seaGreen)
        XCTAssertEqual(VideoFormatStyle.color(for: "3gp"), Color.teal)
        XCTAssertEqual(VideoFormatStyle.color(for: "unknown"), fallback)
        XCTAssertEqual(VideoFormatStyle.color(for: ""), fallback)
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
