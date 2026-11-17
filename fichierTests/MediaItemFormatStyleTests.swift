//
//  MediaItemFormatStyleTests.swift
//  fichierTests
//

#if DEBUG && canImport(XCTest)
import XCTest
import SwiftUI
@testable import fichier
import FichierKit

@MainActor
final class MediaItemFormatStyleTests: XCTestCase {
    
    func testLabels() {
        let pdfItem = MediaItem(name: "document.pdf", path: "document.pdf", isDirectory: false)
        let gifItem = MediaItem(name: "animation.gif", path: "animation.gif", isDirectory: false)
        let mp4Item = MediaItem(name: "clip.mp4", path: "clip.mp4", isDirectory: false)
        let mkvItem = MediaItem(name: "movie.mkv", path: "movie.mkv", isDirectory: false)
        let pngItem = MediaItem(name: "photo.png", path: "photo.png", isDirectory: false)
        let jpgItem = MediaItem(name: "photo.jpg", path: "photo.jpg", isDirectory: false)
        let unnamedItem = MediaItem(name: "unknown", path: "unknown", isDirectory: false)
        
        XCTAssertEqual(MediaItemFormatStyle.label(for: pdfItem), "PDF")
        XCTAssertEqual(MediaItemFormatStyle.label(for: gifItem), "GIF")
        XCTAssertEqual(MediaItemFormatStyle.label(for: mp4Item), "MP4")
        XCTAssertEqual(MediaItemFormatStyle.label(for: mkvItem), "MKV")
        XCTAssertEqual(MediaItemFormatStyle.label(for: pngItem), "PNG")
        XCTAssertEqual(MediaItemFormatStyle.label(for: jpgItem), "JPG")
        XCTAssertEqual(MediaItemFormatStyle.label(for: unnamedItem), "PHOTO")
    }
    
    func testColors() {
        let pdfItem = MediaItem(name: "document.pdf", path: "document.pdf", isDirectory: false)
        let gifItem = MediaItem(name: "animation.gif", path: "animation.gif", isDirectory: false)
        let mp4Item = MediaItem(name: "clip.mp4", path: "clip.mp4", isDirectory: false)
        let mkvItem = MediaItem(name: "movie.mkv", path: "movie.mkv", isDirectory: false)
        let pngItem = MediaItem(name: "photo.png", path: "photo.png", isDirectory: false)
        let jpgItem = MediaItem(name: "photo.jpg", path: "photo.jpg", isDirectory: false)
        let heicItem = MediaItem(name: "photo.heic", path: "photo.heic", isDirectory: false)
        let webpItem = MediaItem(name: "photo.webp", path: "photo.webp", isDirectory: false)
        let dngItem = MediaItem(name: "photo.dng", path: "photo.dng", isDirectory: false)
        
        XCTAssertEqual(MediaItemFormatStyle.color(for: pdfItem), Color(red: 0.90, green: 0.25, blue: 0.25))
        XCTAssertEqual(MediaItemFormatStyle.color(for: gifItem), Color.orange)
        XCTAssertEqual(MediaItemFormatStyle.color(for: mp4Item), Color.blue)
        XCTAssertEqual(MediaItemFormatStyle.color(for: mkvItem), Color(red: 0.58, green: 0.28, blue: 0.88))
        XCTAssertEqual(MediaItemFormatStyle.color(for: pngItem), Color.teal)
        XCTAssertEqual(MediaItemFormatStyle.color(for: jpgItem), Color.green)
        XCTAssertEqual(MediaItemFormatStyle.color(for: heicItem), Color.cyan)
        XCTAssertEqual(MediaItemFormatStyle.color(for: webpItem), Color.blue)
        XCTAssertEqual(MediaItemFormatStyle.color(for: dngItem), Color(red: 0.58, green: 0.28, blue: 0.88))
    }
    
    func testPictograms() {
        let videoItem = MediaItem(name: "clip.mp4", path: "clip.mp4", isDirectory: false)
        let photoItem = MediaItem(name: "photo.jpg", path: "photo.jpg", isDirectory: false)
        let pdfItem = MediaItem(name: "document.pdf", path: "document.pdf", isDirectory: false)
        
        XCTAssertEqual(MediaItemFormatStyle.pictogramName(for: videoItem), "play.fill")
        XCTAssertEqual(MediaItemFormatStyle.pictogramName(for: photoItem), "photo.fill")
        XCTAssertEqual(MediaItemFormatStyle.pictogramName(for: pdfItem), "doc.text.fill")
    }
}
#endif
