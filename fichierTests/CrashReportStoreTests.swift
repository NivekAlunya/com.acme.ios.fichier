//
//  CrashReportStoreTests.swift
//  fichierTests
//

import Foundation
import Testing
import FichierKit
@testable import fichier

@Suite("CrashReportStore")
struct CrashReportStoreTests {

    private func makeStore(max: Int = 10) -> CrashReportStore {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "CrashReportStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return CrashReportStore(directoryURL: dir, maxArchivedReports: max)
    }

    @Test("Returns nil when nothing was archived")
    func emptyStoreHasNoReport() {
        #expect(makeStore().latestReportURL() == nil)
    }

    @Test("Archived report is readable and returned as latest")
    func archiveRoundTrip() throws {
        let store = makeStore()
        let url = try store.archive("boom", date: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try String(contentsOf: url, encoding: .utf8) == "boom")
        #expect(store.latestReportURL() == url)
    }

    @Test("Latest report is the newest, even for same-second crashes")
    func newestWins() throws {
        let store = makeStore()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try store.archive("old", date: date.addingTimeInterval(-60))
        _ = try store.archive("first", date: date)
        let second = try store.archive("second", date: date)
        #expect(store.latestReportURL() == second)
        #expect(try String(contentsOf: second, encoding: .utf8) == "second")
    }

    @Test("Multi-digit same-second crash suffixes maintain true chronological ordering")
    func multiDigitSuffixOrdering() throws {
        let store = makeStore(max: 20)
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        var createdURLs: [URL] = []
        for index in 0...12 {
            let url = try store.archive("crash_\(index)", date: date)
            createdURLs.append(url)
        }

        // The 13th file created (suffix 12 / _012) must be the latest
        let latest = try #require(store.latestReportURL())
        #expect(latest == createdURLs.last)
        #expect(try String(contentsOf: latest, encoding: .utf8) == "crash_12")
    }

    @Test("Old reports are pruned beyond the retention limit")
    func pruning() throws {
        let store = makeStore(max: 2)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<4 {
            _ = try store.archive("r\(index)", date: base.addingTimeInterval(Double(index) * 60))
        }
        let files = try FileManager.default.contentsOfDirectory(at: store.directoryURL, includingPropertiesForKeys: nil)
        #expect(files.count == 2)
        let latest = try #require(store.latestReportURL())
        #expect(try String(contentsOf: latest, encoding: .utf8) == "r3")
    }

    @Test("Credentials embedded in crash URI strings are redacted")
    func credentialRedaction() {
        let textWithSMB = "Fatal error connecting to smb://john_doe:SuperSecret123@192.168.1.100/Media/file.mkv"
        let redactedSMB = CrashReporting.redactCredentials(in: textWithSMB)
        #expect(!redactedSMB.contains("SuperSecret123"))
        #expect(redactedSMB.contains("smb://john_doe:***@192.168.1.100/Media/file.mkv"))

        let textWithHTTP = "Failed request at http://admin:p%40ssword!@127.0.0.1:8080/stream"
        let redactedHTTP = CrashReporting.redactCredentials(in: textWithHTTP)
        #expect(!redactedHTTP.contains("p%40ssword!"))
        #expect(redactedHTTP.contains("http://admin:***@127.0.0.1:8080/stream"))
    }
}
