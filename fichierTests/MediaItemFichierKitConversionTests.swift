//
//  MediaItemFichierKitConversionTests.swift
//  fichierTests
//
//  Created for testing conversions between MediaItem and FichierKit.MediaSourceItem.
//

#if DEBUG
import Foundation
import Testing
import FichierKit
@testable import fichier

@Suite("MediaItem & FichierKit Conversion Tests")
struct MediaItemFichierKitConversionTests {

    @Test("SMB share root converts cleanly with canonical leading slash")
    func smbShareRootConversionAndRoundTrip() {
        let sourceItem = MediaSourceItem(
            id: "alice@nas.local|Movies::/",
            name: "Movies",
            path: "Movies",
            type: .folder,
            size: 0,
            modifiedDate: nil,
            sourceID: "alice@nas.local",
            smbShare: "Movies",
            smbPath: ""
        )

        let mediaItem = MediaItem(sourceItem: sourceItem)
        #expect(mediaItem.locationID == "alice@nas.local")
        #expect(mediaItem.name == "Movies")
        #expect(mediaItem.shareName == "Movies")
        #expect(mediaItem.path == "/")
        #expect(mediaItem.smbRelativePath == "")
        #expect(mediaItem.isDirectory)
        #expect(mediaItem.id == "alice@nas.local|Movies::/")

        let roundTripped = mediaItem.asMediaSourceItem
        #expect(roundTripped.id == mediaItem.id)
        #expect(roundTripped.type == .folder)
        #expect(roundTripped.path == "Movies")
        #expect(roundTripped.smbShare == "Movies")
        #expect(roundTripped.smbPath == "")
        #expect(roundTripped.sourceID == "alice@nas.local")
    }

    @Test("SMB nested video and document items preserve paths, guest connection IDs, and media types")
    func smbFileConversionsAndRoundTrip() {
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let pdfSource = MediaSourceItem(
            id: "192.168.1.50|Docs::/Reports/Q4.pdf",
            name: "Q4.pdf",
            path: "Docs/Reports/Q4.pdf",
            type: .document,
            size: 4096,
            modifiedDate: modified,
            sourceID: "guest@192.168.1.50",
            smbShare: "Docs",
            smbPath: "Reports/Q4.pdf"
        )

        // Explicit locationID override preserves guest connectionID semantics
        let pdfItem = MediaItem(sourceItem: pdfSource, locationID: "192.168.1.50", rootName: "Docs")
        #expect(pdfItem.locationID == "192.168.1.50")
        #expect(pdfItem.path == "/Reports/Q4.pdf")
        #expect(pdfItem.smbRelativePath == "Reports/Q4.pdf")
        #expect(pdfItem.isPDF)
        #expect(pdfItem.isDocument)
        #expect(!pdfItem.isVideo)

        let pdfSourceRoundTrip = pdfItem.asMediaSourceItem
        #expect(pdfSourceRoundTrip.type == .document)
        #expect(pdfSourceRoundTrip.smbShare == "Docs")
        #expect(pdfSourceRoundTrip.smbPath == "Reports/Q4.pdf")
        #expect(pdfSourceRoundTrip.path == "Docs/Reports/Q4.pdf")
        #expect(pdfSourceRoundTrip.size == 4096)
        #expect(pdfSourceRoundTrip.modifiedDate == modified)

        let mkvItem = MediaItem(
            locationID: "alice@nas",
            name: "Clip.mkv",
            rootName: "Media",
            path: "/Trips/Clip.mkv",
            isDirectory: false,
            size: 8192
        )
        let mkvSource = mkvItem.asMediaSourceItem
        #expect(mkvSource.type == .video)
        #expect(mkvSource.smbShare == "Media")
        #expect(mkvSource.smbPath == "Trips/Clip.mkv")
        let mkvBack = MediaItem(sourceItem: mkvSource)
        #expect(mkvBack.id == mkvItem.id)
        #expect(mkvBack.isVideo)
        #expect(mkvBack.path == "/Trips/Clip.mkv")
    }

    @Test("Local URL and PhotoKit items convert accurately between MediaItem and MediaSourceItem")
    func localAndPhotoKitConversions() {
        let localURL = URL(fileURLWithPath: "/tmp/Vacation/Clip.mov")
        let localSource = MediaSourceItem(
            id: "local_1|Vacation::Clip.mov",
            name: "Clip.mov",
            path: "Clip.mov",
            type: .video,
            size: 2048,
            modifiedDate: nil,
            localURL: localURL,
            sourceID: "local_1"
        )

        let localItem = MediaItem(sourceItem: localSource, locationID: "local_1", rootName: "Vacation")
        #expect(localItem.localURL == localURL)
        #expect(localItem.isVideo)
        #expect(localItem.rootName == "Vacation")
        #expect(localItem.locationID == "local_1")

        let localSourceBack = localItem.asMediaSourceItem
        #expect(localSourceBack.type == .video)
        #expect(localSourceBack.localURL == localURL)
        #expect(localSourceBack.smbShare == nil)

        let phAssetSource = MediaSourceItem(
            id: "ph::ABC-123",
            name: "Sunset.HEIC",
            path: "ABC-123",
            type: .image,
            size: 1024,
            phAssetIdentifier: "ABC-123",
            sourceID: StorageLocation.photosLocationID
        )
        let phItem = MediaItem(sourceItem: phAssetSource)
        #expect(phItem.isPhotoAsset)
        #expect(phItem.phAssetIdentifier == "ABC-123")
        #expect(phItem.id == "ph::ABC-123")
        #expect(!phItem.isVideo)

        let phBack = phItem.asMediaSourceItem
        #expect(phBack.phAssetIdentifier == "ABC-123")
        #expect(phBack.type == .image)

        let albumItem = MediaItem(
            locationID: StorageLocation.photosLocationID,
            name: "Favorites",
            rootName: "Photos",
            path: "ALBUM_UUID",
            isDirectory: true
        )
        let albumSource = albumItem.asMediaSourceItem
        #expect(albumSource.id == "album_ALBUM_UUID")
        #expect(albumSource.type == .folder)
        #expect(albumSource.phAssetIdentifier == nil)
    }
}
#endif
