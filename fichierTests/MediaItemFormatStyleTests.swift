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
    
    func testFormatInfo() {
        let pdfItem = MediaItem(name: "document.pdf", path: "document.pdf", isDirectory: false)
        let gifItem = MediaItem(name: "animation.gif", path: "animation.gif", isDirectory: false)
        let emptyExtItem = MediaItem(name: "unknown", path: "unknown", isDirectory: false)
        let uppercaseExtItem = MediaItem(name: "PHOTO.PNG", path: "PHOTO.PNG", isDirectory: false)
        let trailingPunctuationItem = MediaItem(name: "file.jpg..", path: "file.jpg..", isDirectory: false)
        let videoItem = MediaItem(name: "clip.mp4", path: "clip.mp4", isDirectory: false)

        let pdfInfo = MediaItemFormatStyle.formatInfo(for: pdfItem)
        XCTAssertEqual(pdfInfo.label, "PDF")
        XCTAssertEqual(pdfInfo.color, Color(red: 0.90, green: 0.25, blue: 0.25))
        XCTAssertEqual(pdfInfo.pictogramName, "doc.text.fill")

        let gifInfo = MediaItemFormatStyle.formatInfo(for: gifItem)
        XCTAssertEqual(gifInfo.label, "GIF")
        XCTAssertEqual(gifInfo.color, Color.orange)
        XCTAssertEqual(gifInfo.pictogramName, "photo.fill")

        let emptyExtInfo = MediaItemFormatStyle.formatInfo(for: emptyExtItem)
        XCTAssertEqual(emptyExtInfo.label, "PHOTO")
        XCTAssertEqual(emptyExtInfo.color, Color(white: 0.30))
        XCTAssertEqual(emptyExtInfo.pictogramName, "photo.fill")

        let uppercaseExtInfo = MediaItemFormatStyle.formatInfo(for: uppercaseExtItem)
        XCTAssertEqual(uppercaseExtInfo.label, "PNG")
        XCTAssertEqual(uppercaseExtInfo.color, Color.teal)
        XCTAssertEqual(uppercaseExtInfo.pictogramName, "photo.fill")

        let trailingPunctuationInfo = MediaItemFormatStyle.formatInfo(for: trailingPunctuationItem)
        XCTAssertEqual(trailingPunctuationInfo.label, "JPG")
        XCTAssertEqual(trailingPunctuationInfo.color, Color.green)
        XCTAssertEqual(trailingPunctuationInfo.pictogramName, "photo.fill")

        let videoInfo = MediaItemFormatStyle.formatInfo(for: videoItem)
        XCTAssertEqual(videoInfo.label, "MP4")
        XCTAssertEqual(videoInfo.color, Color.blue)
        XCTAssertEqual(videoInfo.pictogramName, "play.fill")
    }
}
#endif
