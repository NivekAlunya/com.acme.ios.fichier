//
//  TVMediaItemFormatStyleTests.swift
//  FichierTVTests
//

#if DEBUG && canImport(XCTest)
import XCTest
import SwiftUI
@testable import FichierTV
import FichierKit

@MainActor
final class TVMediaItemFormatStyleTests: XCTestCase {
    
    func testLabels() {
        let pdfItem = MediaSourceItem(id: "1", name: "document.pdf", path: "document.pdf", type: .image)
        let gifItem = MediaSourceItem(id: "2", name: "animation.gif", path: "animation.gif", type: .image)
        let mp4Item = MediaSourceItem(id: "3", name: "clip.mp4", path: "clip.mp4", type: .video)
        let mkvItem = MediaSourceItem(id: "4", name: "movie.mkv", path: "movie.mkv", type: .video)
        let pngItem = MediaSourceItem(id: "5", name: "photo.png", path: "photo.png", type: .image)
        let jpgItem = MediaSourceItem(id: "6", name: "photo.jpg", path: "photo.jpg", type: .image)
        let unnamedVideo = MediaSourceItem(id: "7", name: "unknown", path: "unknown", type: .video)
        let unnamedImage = MediaSourceItem(id: "8", name: "unknown", path: "unknown", type: .image)
        let folderWithCount = MediaSourceItem(id: "9", name: "Vacation", path: "Vacation", type: .folder, size: 42)
        let emptyFolder = MediaSourceItem(id: "10", name: "Empty", path: "Empty", type: .folder, size: 0)
        
        XCTAssertEqual(TVMediaItemFormatStyle.label(for: pdfItem), "PDF")
        XCTAssertEqual(TVMediaItemFormatStyle.label(for: gifItem), "GIF")
        XCTAssertEqual(TVMediaItemFormatStyle.label(for: mp4Item), "MP4")
        XCTAssertEqual(TVMediaItemFormatStyle.label(for: mkvItem), "MKV")
        XCTAssertEqual(TVMediaItemFormatStyle.label(for: pngItem), "PNG")
        XCTAssertEqual(TVMediaItemFormatStyle.label(for: jpgItem), "JPG")
        XCTAssertEqual(TVMediaItemFormatStyle.label(for: unnamedVideo), "VIDEO")
        XCTAssertEqual(TVMediaItemFormatStyle.label(for: unnamedImage), "PHOTO")
        XCTAssertEqual(TVMediaItemFormatStyle.label(for: folderWithCount), "42")
        XCTAssertEqual(TVMediaItemFormatStyle.label(for: emptyFolder), "FOLDER")
    }
    
    func testColors() {
        let pdfItem = MediaSourceItem(id: "1", name: "document.pdf", path: "document.pdf", type: .image)
        let gifItem = MediaSourceItem(id: "2", name: "animation.gif", path: "animation.gif", type: .image)
        let mp4Item = MediaSourceItem(id: "3", name: "clip.mp4", path: "clip.mp4", type: .video)
        let mkvItem = MediaSourceItem(id: "4", name: "movie.mkv", path: "movie.mkv", type: .video)
        let pngItem = MediaSourceItem(id: "5", name: "photo.png", path: "photo.png", type: .image)
        let jpgItem = MediaSourceItem(id: "6", name: "photo.jpg", path: "photo.jpg", type: .image)
        let heicItem = MediaSourceItem(id: "7", name: "photo.heic", path: "photo.heic", type: .image)
        let webpItem = MediaSourceItem(id: "8", name: "photo.webp", path: "photo.webp", type: .image)
        let dngItem = MediaSourceItem(id: "9", name: "photo.dng", path: "photo.dng", type: .image)
        let folderItem = MediaSourceItem(id: "10", name: "docs", path: "docs", type: .folder)
        
        XCTAssertEqual(TVMediaItemFormatStyle.color(for: pdfItem), Color(red: 0.90, green: 0.25, blue: 0.25))
        XCTAssertEqual(TVMediaItemFormatStyle.color(for: gifItem), Color.orange)
        XCTAssertEqual(TVMediaItemFormatStyle.color(for: mp4Item), Color.blue)
        XCTAssertEqual(TVMediaItemFormatStyle.color(for: mkvItem), Color(red: 0.58, green: 0.28, blue: 0.88))
        XCTAssertEqual(TVMediaItemFormatStyle.color(for: pngItem), Color.teal)
        XCTAssertEqual(TVMediaItemFormatStyle.color(for: jpgItem), Color.green)
        XCTAssertEqual(TVMediaItemFormatStyle.color(for: heicItem), Color.cyan)
        XCTAssertEqual(TVMediaItemFormatStyle.color(for: webpItem), Color.blue)
        XCTAssertEqual(TVMediaItemFormatStyle.color(for: dngItem), Color(red: 0.58, green: 0.28, blue: 0.88))
        XCTAssertEqual(TVMediaItemFormatStyle.color(for: folderItem), Color(white: 0.35))
    }
    
    func testPictograms() {
        let videoItem = MediaSourceItem(id: "1", name: "clip.mp4", path: "clip.mp4", type: .video)
        let photoItem = MediaSourceItem(id: "2", name: "photo.jpg", path: "photo.jpg", type: .image)
        let folderItem = MediaSourceItem(id: "3", name: "Vacation", path: "Vacation", type: .folder)
        
        XCTAssertEqual(TVMediaItemFormatStyle.pictogramName(for: videoItem), "play.fill")
        XCTAssertEqual(TVMediaItemFormatStyle.pictogramName(for: photoItem), "photo.fill")
        XCTAssertEqual(TVMediaItemFormatStyle.pictogramName(for: folderItem), "folder.fill")
    }
}
#endif
