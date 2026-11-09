//
//  SupportedMediaTypesTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
import FichierKit
@testable import fichier

final class SupportedMediaTypesTests: XCTestCase {
    func testPDFTypeSupport() {
        XCTAssertTrue(SupportedMediaTypes.isPDF(extension: "pdf"))
        XCTAssertTrue(SupportedMediaTypes.isPDF(extension: "PDF"))
        XCTAssertTrue(SupportedMediaTypes.isDocument(extension: "pdf"))
        XCTAssertFalse(SupportedMediaTypes.isPDF(extension: "png"))
        XCTAssertFalse(SupportedMediaTypes.isDocument(extension: "jpg"))
        XCTAssertTrue(SupportedMediaTypes.allExtensions.contains("pdf"))
    }
    
    func testNativeVideoTypeSupport() {
        XCTAssertTrue(SupportedMediaTypes.isNativeVideo(extension: "mp4"))
        XCTAssertTrue(SupportedMediaTypes.isNativeVideo(extension: "MOV"))
        XCTAssertTrue(SupportedMediaTypes.isNativeVideo(extension: "m4v"))
        XCTAssertTrue(SupportedMediaTypes.isNativeVideo(extension: "3gp"))
        XCTAssertTrue(SupportedMediaTypes.isVideo(extension: "mp4"))
        XCTAssertFalse(SupportedMediaTypes.isExtendedVideo(extension: "mp4"))
    }
    
    func testExtendedVideoTypeSupport() {
        let extendedExts = ["mkv", "avi", "webm", "flv", "f4v", "wmv", "asf", "ts", "m2ts", "mts", "m2v", "mpg", "mpeg", "vob", "ogv", "rm", "mxf", "wtv", "hevc", "mjpeg"]
        for ext in extendedExts {
            XCTAssertTrue(SupportedMediaTypes.isVideo(extension: ext), "Expected \(ext) to be recognized as video")
            XCTAssertTrue(SupportedMediaTypes.isExtendedVideo(extension: ext), "Expected \(ext) to be extended video")
            XCTAssertFalse(SupportedMediaTypes.isNativeVideo(extension: ext), "Expected \(ext) to not be native video")
            XCTAssertTrue(SupportedMediaTypes.isSupported(extension: ext), "Expected \(ext) to be supported")
        }
    }
    
    func testMimeTypeResolution() {
        // Extended container MIME mapping with and without leading dot
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "mkv"), "video/x-matroska")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: ".mkv"), "video/x-matroska")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "MKV"), "video/x-matroska")
        
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "webm"), "video/webm")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: ".webm"), "video/webm")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "WEBM"), "video/webm")
        
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "avi"), "video/x-msvideo")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: ".avi"), "video/x-msvideo")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "AVI"), "video/x-msvideo")
        
        // Native video formats
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "mp4"), "video/mp4")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: ".mp4"), "video/mp4")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "mov"), "video/quicktime")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: ".mov"), "video/quicktime")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "m4v"), "video/x-m4v")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "3gp"), "video/3gpp")
        
        // Other extended containers
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "wmv"), "video/x-ms-wmv")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "asf"), "video/x-ms-wmv")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "flv"), "video/x-flv")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "f4v"), "video/x-flv")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "ts"), "video/mp2t")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "m2ts"), "video/mp2t")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "mts"), "video/mp2t")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "ogv"), "video/ogg")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "rm"), "application/vnd.rn-realmedia")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "mxf"), "application/mxf")
        
        // Documents & Images
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: "pdf"), "application/pdf")
        XCTAssertEqual(SupportedMediaTypes.mimeType(for: ".pdf"), "application/pdf")
    }
}
#endif
