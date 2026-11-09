//
//  TVVideoThumbnailHostTests.swift
//  FichierTVTests
//

import Foundation
import Photos
import Testing
import UIKit
@testable import FichierTV
import FichierKit

@Suite("Host App Video Thumbnail Tests")
struct TVVideoThumbnailHostTests {
    @Test("Extracts SMB native MP4 and extended MKV video thumbnails inside FichierTV app host")
    func testHostSMBAndVLCVideoThumbnailGeneration() async throws {
        let tempVideoURL = try await TVVideoTestFixtureGenerator.createSampleMP4File()
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        let mp4Data = try Data(contentsOf: tempVideoURL)
        let server = SavedSMBConnection(host: "192.168.1.90", username: "guest", lastConnected: Date())
        let client = StubHostSMBClient(
            mockShares: ["Movies"],
            mockFileData: [
                "Movies/feature.mp4": mp4Data,
                "Movies/feature.mkv": mp4Data
            ]
        )
        let source = SharesMediaSource(server: server, client: client)
        let resolver = DefaultMediaSourceResolver()
        await resolver.register(source: source)

        let loader = SMBVideoThumbnailLoader()
        let mp4Thumb = await loader.loadThumbnail(
            sourceID: server.id,
            share: "Movies",
            path: "feature.mp4",
            fileName: "feature.mp4",
            fileSize: Int64(mp4Data.count),
            targetSize: CGSize(width: 380, height: 260),
            resolver: resolver
        )
        let mp4Image = try #require(mp4Thumb)
        #expect(mp4Image.size.width > 0)

        let mkvThumb = await loader.loadThumbnail(
            sourceID: server.id,
            share: "Movies",
            path: "feature.mkv",
            fileName: "feature.mkv",
            fileSize: Int64(mp4Data.count),
            targetSize: CGSize(width: 120, height: 80),
            resolver: resolver
        )
        let mkvImage = try #require(mkvThumb)
        #expect(mkvImage.size.width > 0)
    }

    @Test("Generates thumbnail for authorized PhotoKit video assets when present in simulator library")
    func testPhotoKitVideoThumbnailIfAuthorized() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        let videos = PHAsset.fetchAssets(with: .video, options: fetchOptions)
        guard let videoAsset = videos.firstObject else {
            return
        }

        let thumb = await PhotoThumbnailLoader.shared.loadThumbnail(
            for: videoAsset.localIdentifier,
            targetSize: CGSize(width: 380, height: 260)
        )
        let image = try #require(thumb)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)

        // Second call serves cached thumbnail cleanly for compact List size
        let listThumb = await PhotoThumbnailLoader.shared.loadThumbnail(
            for: videoAsset.localIdentifier,
            targetSize: CGSize(width: 120, height: 80)
        )
        #expect(listThumb != nil)
    }

    @Test("PhotosMediaSource sorts albums and album assets by filename ascending without PHFetchOptions crash")
    func testPhotosMediaSourceFilenameSortWhenAuthorized() async throws {
        let source = PhotosMediaSource()
        guard source.authorizationStatus == .authorized || source.authorizationStatus == .limited else {
            return
        }

        let albums = try await source.fetchItems(
            in: nil,
            sortBy: .name,
            order: .ascending,
            page: 0,
            pageSize: 40
        )
        #expect(!albums.isEmpty)

        if let firstAlbum = albums.first {
            let assets = try await source.fetchItems(
                in: firstAlbum,
                sortBy: .name,
                order: .ascending,
                page: 0,
                pageSize: 40
            )
            if assets.count > 1 {
                #expect(assets[0].name.localizedStandardCompare(assets[1].name) != .orderedDescending)
            }
        }
    }
}
