//
//  ThumbnailCachingAndCancellationTests.swift
//  fichierTests
//
//  Created for testing thumbnail loading, RAM/disk cache hits, invalidation, and task cancellation.
//

#if DEBUG
import UIKit
import Testing
import FichierKit
@testable import fichier

@Suite("Thumbnail Caching & Cancellation Tests")
@MainActor
struct ThumbnailCachingAndCancellationTests {

    private func makeTestPNGData(color: UIColor = .systemBlue) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        return image.pngData() ?? Data()
    }

    private func makeManager(client: MockSMBClient) async -> (manager: StorageLocationManager, defaults: UserDefaults, suiteName: String) {
        let suiteName = "com.acme.ios.fichier.tests.thumbs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let passwordStore = SMBPasswordStore(service: "com.acme.ios.fichier.tests.\(UUID().uuidString)")
        let store = StorageLocationPersistenceStore(userDefaults: defaults, passwordStore: passwordStore)
        let worker = SMBClientActor { _, _ in client }
        let manager = StorageLocationManager(worker: worker, persistenceStore: store)
        await manager.connect(host: "nas.local", user: "alice", pass: "secret")
        return (manager, defaults, suiteName)
    }

    @Test("Thumbnail pipeline caches hits in RAM and disk and re-fetches after invalidation")
    func cacheHitMissAndInvalidationLifecycle() async {
        let pngData = makeTestPNGData()
        #expect(!pngData.isEmpty)

        let uniqueName = "photo_\(UUID().uuidString).png"
        let folderSource = MediaSourceItem(
            id: "folder-thumbs",
            name: "Thumbs",
            path: "Media/Thumbs",
            type: .folder,
            smbShare: "Media",
            smbPath: "Thumbs"
        )
        let fileSource = MediaSourceItem(
            id: "file-thumb",
            name: uniqueName,
            path: "Media/Thumbs/\(uniqueName)",
            type: .image,
            size: Int64(pngData.count),
            smbShare: "Media",
            smbPath: "Thumbs/\(uniqueName)"
        )

        let client = MockSMBClient(
            shares: ["Media"],
            directoryContents: [
                "Media": [folderSource],
                "Media/Thumbs": [fileSource]
            ],
            fileData: ["Media/Thumbs/\(uniqueName)": pngData]
        )

        let (manager, defaults, suiteName) = await makeManager(client: client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folderItem = MediaItem(
            locationID: "alice@nas.local",
            name: "Thumbs",
            rootName: "Media",
            path: "/Thumbs",
            isDirectory: true
        )
        await manager.selectAndLoadFolder(folderItem)
        let targetItem = manager.pictures[0]
        defer {
            Task { await MediaCacheManager.shared.invalidateThumbnailCache(for: [targetItem]) }
        }

        let (diskKey, _, _) = MediaCacheManager.shared.thumbnailKeys(
            for: targetItem.shareName,
            path: targetItem.path,
            dimension: 260,
            connectionID: targetItem.connectionID
        )
        #expect(!MediaCacheManager.shared.hasThumbnail(for: diskKey))

        // 1. Cache miss -> downloads once and populates RAM + disk cache
        let firstThumb = await manager.downloadThumbnail(for: targetItem, maxDimension: 260)
        #expect(firstThumb != nil)
        #expect(await client.readFileCalls.count == 1)
        #expect(MediaCacheManager.shared.hasThumbnail(for: diskKey))

        // 2. RAM cache hit -> does not re-read from client
        let ramHit = await manager.downloadThumbnail(for: targetItem, maxDimension: 260)
        #expect(ramHit != nil)
        #expect(await client.readFileCalls.count == 1)

        // 3. Flush RAM cache only -> disk cache hit does not re-read from client
        await manager.clientActor.clearMemoryCache()
        let diskHit = await manager.downloadThumbnail(for: targetItem, maxDimension: 260)
        #expect(diskHit != nil)
        #expect(await client.readFileCalls.count == 1)

        // 4. Invalidate current folder -> deletes disk cache, evicts RAM, bumps observable version
        let versionBefore = manager.thumbnailVersions[targetItem.id] ?? 0
        await manager.invalidateCurrentFolderThumbnails()
        #expect(!MediaCacheManager.shared.hasThumbnail(for: diskKey))
        #expect((manager.thumbnailVersions[targetItem.id] ?? 0) == versionBefore + 1)

        // 5. After invalidation, next fetch hits SMB client again
        let refetchedThumb = await manager.downloadThumbnail(for: targetItem, maxDimension: 260)
        #expect(refetchedThumb != nil)
        #expect(await client.readFileCalls.count == 2)
    }

    @Test("Cancelled thumbnail request returns nil without populating caches")
    func cancelledThumbnailRequestReturnsNilWithoutCaching() async {
        let pngData = makeTestPNGData()
        let uniqueName = "cancel_\(UUID().uuidString).png"
        let fileKey = "Media/Folder/\(uniqueName)"
        let fileSource = MediaSourceItem(
            id: "file-cancel",
            name: uniqueName,
            path: fileKey,
            type: .image,
            size: Int64(pngData.count),
            smbShare: "Media",
            smbPath: "Folder/\(uniqueName)"
        )
        let client = MockSMBClient(
            shares: ["Media"],
            directoryContents: ["Media/Folder": [fileSource]],
            fileData: [fileKey: pngData]
        )
        let (manager, defaults, suiteName) = await makeManager(client: client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folderItem = MediaItem(
            locationID: "alice@nas.local",
            name: "Folder",
            rootName: "Media",
            path: "/Folder",
            isDirectory: true
        )
        await manager.selectAndLoadFolder(folderItem)
        let targetItem = manager.pictures[0]
        defer {
            Task { await MediaCacheManager.shared.invalidateThumbnailCache(for: [targetItem]) }
        }

        await client.armReadGate(forKey: fileKey)
        let thumbTask = Task {
            await manager.downloadThumbnail(for: targetItem, maxDimension: 260)
        }
        await client.waitUntilReadStarts(forKey: fileKey)
        thumbTask.cancel()
        await client.releaseReadGate(forKey: fileKey)

        let result = await thumbTask.value
        #expect(result == nil)

        let (diskKey, _, _) = MediaCacheManager.shared.thumbnailKeys(
            for: targetItem.shareName,
            path: targetItem.path,
            dimension: 260,
            connectionID: targetItem.connectionID
        )
        #expect(!MediaCacheManager.shared.hasThumbnail(for: diskKey))
    }

    @Test("Stale folder thumbnail request returns nil without issuing network read")
    func staleFolderMismatchSkipsThumbnailDownload() async {
        let pngData = makeTestPNGData()
        let client = MockSMBClient(
            shares: ["Media"],
            directoryContents: [:],
            fileData: ["Media/FolderA/old.png": pngData]
        )
        let (manager, defaults, suiteName) = await makeManager(client: client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folderB = MediaItem(
            locationID: "alice@nas.local",
            name: "FolderB",
            rootName: "Media",
            path: "/FolderB",
            isDirectory: true
        )
        await manager.selectAndLoadFolder(folderB)

        let staleItem = MediaItem(
            locationID: "alice@nas.local",
            name: "old.png",
            rootName: "Media",
            path: "/FolderA/old.png",
            isDirectory: false,
            size: Int64(pngData.count)
        )

        let result = await manager.downloadThumbnail(for: staleItem, maxDimension: 260)
        #expect(result == nil)
        #expect(await client.readFileCalls.isEmpty)
    }
}
#endif
