//
//  MockSMBDirectoryPageCall.swift
//  fichierTests
//
//

#if DEBUG
import Foundation
import FichierKit

/// Records the parameters passed to `MockSMBClient.listDirectoryPage` for pagination assertions.
nonisolated struct MockSMBDirectoryPageCall: Sendable, Equatable {
    let key: String
    let cursor: String?
    let pageSize: Int
    let sortKey: MediaSortKey
    let sortOrder: MediaSortOrder
}
#endif
