//
//  ThumbnailReviewRegressionTests.swift
//  fichierTests
//
//

import XCTest
import FichierKit
@testable import Fichier

final class ThumbnailReviewRegressionTests: XCTestCase {

    func testThumbnailCacheSubPathAndLegacyV7Cleanup() async {
        let manager = MediaCacheManager.shared
        let item = MediaItem(
            locationID: "test_loc",
            name: "clip.mp4",
            rootName: "share",
            path: "/videos/clip.mp4",
            isDirectory: false
        )

        #if DEBUG
        XCTAssertEqual(
            MediaCacheManager.thumbnailCacheSubPath(for: item.path, isVideo: true),
            "/videos/clip.mp4_vidstream_v14"
        )
        #else
        XCTAssertEqual(
            MediaCacheManager.thumbnailCacheSubPath(for: item.path, isVideo: true),
            "/videos/clip.mp4"
        )
        #endif
        XCTAssertEqual(
            MediaCacheManager.thumbnailCacheSubPath(for: "/photos/pic.jpg", isVideo: false),
            "/photos/pic.jpg"
        )

        let currentSubPath = MediaCacheManager.thumbnailCacheSubPath(for: item.path, isVideo: true)
        let (currentKey, _, _) = manager.thumbnailKeys(
            for: item.shareName,
            path: currentSubPath,
            dimension: MediaCacheManager.standardThumbnailDimension,
            connectionID: item.connectionID
        )
        let (legacyV7Key, _, _) = manager.thumbnailKeys(
            for: item.shareName,
            path: "\(item.path)_vidstream_v7",
            dimension: MediaCacheManager.standardThumbnailDimension,
            connectionID: item.connectionID
        )

        let sampleImage = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        manager.saveThumbnail(sampleImage, for: currentKey)
        manager.saveThumbnail(sampleImage, for: legacyV7Key)
        XCTAssertTrue(manager.hasThumbnail(for: currentKey))
        XCTAssertTrue(manager.hasThumbnail(for: legacyV7Key))

        await manager.invalidateThumbnailCache(for: [item])
        XCTAssertFalse(manager.hasThumbnail(for: currentKey))
        XCTAssertFalse(manager.hasThumbnail(for: legacyV7Key))
    }

    func testMigrateThumbnailCacheUsesCanonicalSubPath() async {
        let manager = MediaCacheManager.shared
        let source = MediaItem(
            locationID: "test_loc",
            name: "old.mp4",
            rootName: "share",
            path: "/videos/old.mp4",
            isDirectory: false
        )
        let destination = MediaItem(
            locationID: "test_loc",
            name: "new.mp4",
            rootName: "share",
            path: "/videos/new.mp4",
            isDirectory: false
        )

        let (sourceKey, _, _) = manager.thumbnailKeys(
            for: source.shareName,
            path: MediaCacheManager.thumbnailCacheSubPath(for: source.path, isVideo: true),
            dimension: MediaCacheManager.standardThumbnailDimension,
            connectionID: source.connectionID
        )
        let (destKey, _, _) = manager.thumbnailKeys(
            for: destination.shareName,
            path: MediaCacheManager.thumbnailCacheSubPath(for: destination.path, isVideo: true),
            dimension: MediaCacheManager.standardThumbnailDimension,
            connectionID: destination.connectionID
        )

        let sampleImage = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        manager.saveThumbnail(sampleImage, for: sourceKey)
        await manager.migrateThumbnailCache(from: source, to: destination)

        XCTAssertFalse(manager.hasThumbnail(for: sourceKey))
        XCTAssertTrue(manager.hasThumbnail(for: destKey))

        await manager.invalidateThumbnailCache(for: [destination])
    }

    func testMediaItemPhotoSubtypePreservationAcrossConversions() {
        let sourceItem = MediaSourceItem(
            id: "smb_item_1",
            name: "burst.webp",
            path: "/photos/burst.webp",
            type: .image,
            size: 1024,
            sourceID: "loc_1",
            photoSubtype: .animated
        )

        let mediaItem = MediaItem(sourceItem: sourceItem, locationID: "loc_1", rootName: "share")
        XCTAssertEqual(mediaItem.photoSubtype, PhotoSubtype.animated)
        XCTAssertEqual(mediaItem.withSize(2048).photoSubtype, PhotoSubtype.animated)
        XCTAssertEqual(mediaItem.asMediaSourceItem.photoSubtype, PhotoSubtype.animated)
    }

    @MainActor
    func testStorageLocationManagerCachedThumbnailHitsDiskWithoutNetwork() async {
        let storageManager = StorageLocationManager()
        let item = MediaItem(
            locationID: "test_cache_only",
            name: "poster.jpg",
            rootName: "share",
            path: "/photos/poster.jpg",
            isDirectory: false
        )

        await MediaCacheManager.shared.invalidateThumbnailCache(for: [item])
        let missing = await storageManager.cachedThumbnail(for: item)
        XCTAssertNil(missing)

        let (diskKey, _, _) = MediaCacheManager.shared.thumbnailKeys(
            for: item.shareName,
            path: MediaCacheManager.thumbnailCacheSubPath(for: item.path, isVideo: false),
            dimension: MediaCacheManager.standardThumbnailDimension,
            connectionID: item.connectionID
        )
        let sampleImage = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { ctx in
            ctx.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        await MediaCacheManager.shared.saveThumbnailAsync(sampleImage, for: diskKey)

        let cached = await storageManager.cachedThumbnail(for: item)
        XCTAssertNotNil(cached)

        await MediaCacheManager.shared.invalidateThumbnailCache(for: [item])
    }
}
