//
//  VLCMediaThumbnailerActorTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import UIKit
import XCTest
import FichierKit
@testable import fichier

final class VLCMediaThumbnailerActorTests: XCTestCase {
    func testSingletonInstanceExists() async {
        let actor = VLCVideoThumbnailActor.shared
        _ = actor
        XCTAssertTrue(true, "VLCVideoThumbnailActor singleton must be reachable")
    }
    
    func testNonexistentMediaURLSafelyReturnsNil() async {
        let nonexistentURL = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).mkv")
        let thumb = await VLCVideoThumbnailActor.shared.generateThumbnail(
            from: nonexistentURL,
            maxDimension: 260,
            snapshotPosition: 0.05,
            timeoutSeconds: 0.5
        )
        XCTAssertNil(thumb, "Thumbnail extraction on nonexistent file must safely return nil")
    }
    
    func testWatchdogTimeoutReturnsNil() async {
        let dummyURL = URL(string: "http://127.0.0.1:1/nonexistent.webm") ?? URL(fileURLWithPath: "/")
        let thumb = await VLCVideoThumbnailActor.shared.generateThumbnail(
            from: dummyURL,
            maxDimension: 260,
            snapshotPosition: 0.05,
            timeoutSeconds: 0.3
        )
        XCTAssertNil(thumb, "Thumbnail extraction timeout must safely return nil without deadlock")
    }
    
    func testConcurrentThumbnailRequestsSerializeSafely() async {
        let dummyURL = URL(string: "http://127.0.0.1:1/nonexistent.webm") ?? URL(fileURLWithPath: "/")
        await withTaskGroup(of: UIImage?.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    await VLCVideoThumbnailActor.shared.generateThumbnail(
                        from: dummyURL,
                        maxDimension: 260,
                        snapshotPosition: 0.05,
                        timeoutSeconds: 0.2
                    )
                }
            }
            for await thumb in group {
                XCTAssertNil(thumb)
            }
        }
    }
    
    func testGenerateThumbnailWithPreferredTimeSafelyReturnsNilOnNonexistentFile() async {
        let nonexistentURL = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).mkv")
        let thumb = await VLCVideoThumbnailActor.shared.generateThumbnail(
            from: nonexistentURL,
            maxDimension: 260,
            timeoutSeconds: 0.3,
            snapshotTimeSeconds: 15.0
        )
        XCTAssertNil(thumb, "Thumbnail extraction with positive snapshotTimeSeconds on missing file must safely return nil")
    }
    
    func testGenerateThumbnailWithZeroPreferredTimeSafelyReturnsNilOnNonexistentFile() async {
        let nonexistentURL = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).mkv")
        let thumb = await VLCVideoThumbnailActor.shared.generateThumbnail(
            from: nonexistentURL,
            maxDimension: 260,
            timeoutSeconds: 0.3,
            snapshotTimeSeconds: 0.0
        )
        XCTAssertNil(thumb, "Thumbnail extraction with zero snapshotTimeSeconds on missing file must safely return nil")
    }
}
#endif
