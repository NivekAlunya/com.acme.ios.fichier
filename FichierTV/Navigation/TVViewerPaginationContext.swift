//
//  TVViewerPaginationContext.swift
//  FichierTV
//
//

import Foundation
import FichierKit

/// Pagination metadata enabling full-screen media viewers to load additional pages beyond the initial browser slice.
public struct TVViewerPaginationContext: Hashable, Sendable {
    public let sourceID: String
    public let folder: MediaSourceItem?
    public let sortKey: MediaSortKey
    public let sortOrder: MediaSortOrder
    public let nextPage: Int
    public let canLoadMore: Bool
    public let pageSize: Int

    public init(
        sourceID: String,
        folder: MediaSourceItem?,
        sortKey: MediaSortKey,
        sortOrder: MediaSortOrder,
        nextPage: Int,
        canLoadMore: Bool,
        pageSize: Int
    ) {
        self.sourceID = sourceID
        self.folder = folder
        self.sortKey = sortKey
        self.sortOrder = sortOrder
        self.nextPage = nextPage
        self.canLoadMore = canLoadMore
        self.pageSize = pageSize
    }
}
