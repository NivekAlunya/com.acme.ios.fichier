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
}
#endif
