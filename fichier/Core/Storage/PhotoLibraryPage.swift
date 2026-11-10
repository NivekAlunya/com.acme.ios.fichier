//
//  PhotoLibraryPage.swift
//  fichier
//
//

import Foundation

/// Bounded page of PhotoKit enumeration results segregated into albums and media assets.
nonisolated public struct PhotoLibraryPage: Sendable {
    /// Album entries returned in this page.
    public let subfolders: [MediaItem]

    /// Photo and video assets returned in this page.
    public let media: [MediaItem]

    /// Next 0-based page index if more items remain, or `nil` when exhausted.
    public let nextPage: Int?

    public init(subfolders: [MediaItem], media: [MediaItem], nextPage: Int?) {
        self.subfolders = subfolders
        self.media = media
        self.nextPage = nextPage
    }
}
