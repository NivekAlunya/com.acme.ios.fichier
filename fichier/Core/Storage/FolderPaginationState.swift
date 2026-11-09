//
//  FolderPaginationState.swift
//  fichier
//
//

import Foundation
import FichierKit

/// Tracks active cursor/page progress and sort configuration for a paginated folder.
nonisolated struct FolderPaginationState: Sendable, Equatable {
    enum Backend: Sendable, Equatable {
        case smb
        case photos
        case local
    }

    let folderID: String
    let backend: Backend
    var smbCursor: String?
    var nextPhotoPage: Int?
    var sortKey: MediaSortKey
    var sortOrder: MediaSortOrder
    var hasMore: Bool
    var consecutiveEmptyPages: Int = 0
}
