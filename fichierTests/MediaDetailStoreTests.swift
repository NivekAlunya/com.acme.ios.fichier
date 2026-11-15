//
//  MediaDetailStoreTests.swift
//  fichierTests
//
//

#if DEBUG && canImport(XCTest)
import XCTest
import FichierKit
@testable import fichier

@MainActor
final class MediaDetailStoreTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        MediaDetailStore.shared.clearCache()
    }

    override func tearDown() async throws {
        MediaDetailStore.shared.clearCache()
        try await super.tearDown()
    }

    func testDurationFormatting() {
        XCTAssertEqual(MediaFormatHelper.formatDuration(0), "")
        XCTAssertEqual(MediaFormatHelper.formatDuration(-15), "")
        XCTAssertEqual(MediaFormatHelper.formatDuration(Double.nan), "")
        XCTAssertEqual(MediaFormatHelper.formatDuration(Double.infinity), "")

        XCTAssertEqual(MediaFormatHelper.formatDuration(12), "00:12")
        XCTAssertEqual(MediaFormatHelper.formatDuration(165), "02:45")
        XCTAssertEqual(MediaFormatHelper.formatDuration(3600), "1:00:00")
        XCTAssertEqual(MediaFormatHelper.formatDuration(4530), "1:15:30")
        XCTAssertEqual(MediaFormatHelper.formatDuration(Double.greatestFiniteMagnitude), "")
        XCTAssertEqual(MediaFormatHelper.formatDuration(Double(Int.max) * 2), "")
    }

    func testDimensionsFormatting() {
        XCTAssertEqual(MediaFormatHelper.formatDimensions(width: 0, height: 0), "")
        XCTAssertEqual(MediaFormatHelper.formatDimensions(width: -100, height: 200), "")
        XCTAssertEqual(MediaFormatHelper.formatDimensions(width: 1920, height: 1080), "1920 × 1080")
        XCTAssertEqual(MediaFormatHelper.formatDimensions(width: 3840, height: 2160), "3840 × 2160")
    }

    func testPageCountFormatting() {
        XCTAssertEqual(MediaFormatHelper.formatPageCount(0), "")
        XCTAssertEqual(MediaFormatHelper.formatPageCount(-1), "")
        XCTAssertEqual(MediaFormatHelper.formatPageCount(1), "1 page")
        XCTAssertEqual(MediaFormatHelper.formatPageCount(12), "12 pages")
    }

    func testMediaDetailStoreCacheAndRegistration() {
        let store = MediaDetailStore.shared
        let itemID = "item-img-99"

        XCTAssertNil(store.cachedDetail(for: itemID))

        store.registerDetail("3840 × 2160", for: itemID)
        XCTAssertEqual(store.cachedDetail(for: itemID), "3840 × 2160")

        store.clearCache()
        XCTAssertNil(store.cachedDetail(for: itemID))
    }

    func testResolveFolderReturnsNil() async {
        let store = MediaDetailStore.shared
        let folderItem = MediaSourceItem(
            id: "folder-test",
            name: "Vacation",
            path: "Vacation",
            type: .folder
        )

        let detail = await store.resolveDetail(for: folderItem)
        XCTAssertNil(detail)
    }

    func testResolvePDFReturnsNil() async {
        let store = MediaDetailStore.shared
        let pdfItem = MediaSourceItem(
            id: "pdf-test",
            name: "Doc.pdf",
            path: "Doc.pdf",
            type: .document
        )

        let detail = await store.resolveDetail(for: pdfItem)
        XCTAssertNil(detail)
    }

    func testVideoPlaybackStoreRegistersDurationWithDetailStore() {
        let store = MediaDetailStore.shared
        let videoItem = MediaItem(
            locationID: "smb_1",
            name: "clip.mp4",
            rootName: "Videos",
            path: "clip.mp4",
            isDirectory: false,
            size: 10240
        )

        VideoPlaybackStore.shared.savePosition(5.0, duration: 165.0, for: videoItem)

        let cached = store.cachedDetail(for: videoItem.id)
        XCTAssertEqual(cached, "02:45")
    }

    func testConcurrentResolutionDeduplication() async {
        let store = MediaDetailStore.shared
        store.clearCache()

        let folderItem = MediaSourceItem(
            id: "dedup-folder-ios",
            name: "Folder",
            path: "Folder",
            type: .folder
        )

        async let first = store.resolveDetail(for: folderItem)
        async let second = store.resolveDetail(for: folderItem)
        async let third = store.resolveDetail(for: folderItem)

        let (r1, r2, r3) = await (first, second, third)
        XCTAssertNil(r1)
        XCTAssertNil(r2)
        XCTAssertNil(r3)
    }
}
#endif
