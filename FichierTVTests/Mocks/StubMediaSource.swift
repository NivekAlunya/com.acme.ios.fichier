//
//  StubMediaSource.swift
//  FichierTVTests
//
//

import Foundation
import FichierKit

final class StubMediaSource: MediaSource, Sendable {
    let id: String
    let displayName: String
    let preferredLayout: MediaSourceLayout
    let supportedSortKeys: Set<MediaSortKey>
    private let items: [MediaSourceItem]
    private let simulatedError: Error?
    private let fetchDelayNanoseconds: UInt64

    init(
        id: String = "stub-source",
        displayName: String = "Stub Source",
        preferredLayout: MediaSourceLayout = .grid,
        supportedSortKeys: Set<MediaSortKey> = [.date, .name],
        items: [MediaSourceItem] = [],
        simulatedError: Error? = nil,
        fetchDelayNanoseconds: UInt64 = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.preferredLayout = preferredLayout
        self.supportedSortKeys = supportedSortKeys
        self.items = items
        self.simulatedError = simulatedError
        self.fetchDelayNanoseconds = fetchDelayNanoseconds
    }

    func fetchItems(
        in folder: MediaSourceItem?,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        page: Int,
        pageSize: Int
    ) async throws -> [MediaSourceItem] {
        if fetchDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: fetchDelayNanoseconds)
        }
        if let simulatedError {
            throw simulatedError
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
