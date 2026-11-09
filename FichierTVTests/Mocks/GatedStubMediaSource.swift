//
//  GatedStubMediaSource.swift
//  FichierTVTests
//
//

import Foundation
import FichierKit

/// Deterministic `MediaSource` test double that can pause a targeted page fetch mid-flight until released.
actor GatedStubMediaSource: MediaSource {
    nonisolated let id: String
    nonisolated let displayName: String
    nonisolated let preferredLayout: MediaSourceLayout
    nonisolated let supportedSortKeys: Set<MediaSortKey>

    private let items: [MediaSourceItem]
    private var gatedPage: Int?
    private var gatedSortKey: MediaSortKey?
    private var gatedError: Error?
    private var hasStartedGatedFetch: Bool = false
    private var isGateReleased: Bool = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var requestedPages: [Int] = []

    init(
        id: String = "gated-stub-source",
        displayName: String = "Gated Stub Source",
        preferredLayout: MediaSourceLayout = .grid,
        supportedSortKeys: Set<MediaSortKey> = [.date, .name],
        items: [MediaSourceItem]
    ) {
        self.id = id
        self.displayName = displayName
        self.preferredLayout = preferredLayout
        self.supportedSortKeys = supportedSortKeys
        self.items = items
    }

    func armGate(forPage page: Int, sortKey: MediaSortKey? = nil, errorAfterGate: Error? = nil) {
        gatedPage = page
        gatedSortKey = sortKey
        gatedError = errorAfterGate
        hasStartedGatedFetch = false
        isGateReleased = false
    }

    func waitUntilGatedFetchStarts() async {
        if hasStartedGatedFetch {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiter = continuation
        }
    }

    func releaseGate() {
        isGateReleased = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func fetchItems(
        in folder: MediaSourceItem?,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        page: Int,
        pageSize: Int
    ) async throws -> [MediaSourceItem] {
        requestedPages.append(page)

        let shouldGate = gatedPage == page && (gatedSortKey == nil || gatedSortKey == sortKey)
        if shouldGate {
            gatedPage = nil
            gatedSortKey = nil
            let errorToThrow = gatedError
            gatedError = nil
            hasStartedGatedFetch = true
            startWaiter?.resume()
            startWaiter = nil

            if !isGateReleased {
                await withCheckedContinuation { continuation in
                    releaseWaiter = continuation
                }
            }

            if let errorToThrow {
                throw errorToThrow
            }
        }

        let sorted = items.sorted { lhs, rhs in
            switch sortKey {
            case .name:
                return sortOrder == .ascending
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            case .date:
                let lDate = lhs.modifiedDate ?? .distantPast
                let rDate = rhs.modifiedDate ?? .distantPast
                return sortOrder == .ascending ? lDate < rDate : lDate > rDate
            case .size:
                return sortOrder == .ascending ? lhs.size < rhs.size : lhs.size > rhs.size
            case .type:
                return sortOrder == .ascending ? lhs.name < rhs.name : lhs.name > rhs.name
            }
        }

        let startIndex = page * pageSize
        guard startIndex < sorted.count else { return [] }
        let endIndex = min(startIndex + pageSize, sorted.count)
        return Array(sorted[startIndex..<endIndex])
    }
}
