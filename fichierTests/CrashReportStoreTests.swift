//
//  CrashReportStoreTests.swift
//  fichierTests
//

import Foundation
import Testing
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
}
