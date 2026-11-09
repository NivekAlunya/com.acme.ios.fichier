//
//  SMBFolderPage.swift
//  fichier
//
//

import Foundation

/// Bounded page of SMB folder enumeration results segregated into subfolders and media items.
nonisolated struct SMBFolderPage: Sendable {
    /// Subfolder entries returned in this page.
    let folders: [MediaItem]

    /// Supported media file entries returned in this page.
    let pictures: [MediaItem]

    /// Opaque continuation cursor for fetching the next page, or `nil` when complete.
    let nextCursor: String?

    /// Total number of filtered entries in the directory when reported by the backend.
    let totalCount: Int?
}
