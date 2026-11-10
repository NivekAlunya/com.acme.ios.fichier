//
//  SortOption+FichierKit.swift
//  fichier
//
//

import FichierKit

extension SortOption {
    /// Corresponding `FichierKit.MediaSortKey` used for backend-level sorting and pagination.
    var mediaSortKey: MediaSortKey {
        switch self {
        case .nameAsc, .nameDesc:
            return .name
        case .dateDesc, .dateAsc:
            return .date
        case .sizeDesc, .sizeAsc:
            return .size
        }
    }

    /// Corresponding `FichierKit.MediaSortOrder` used for backend-level sorting and pagination.
    var mediaSortOrder: MediaSortOrder {
        switch self {
        case .nameAsc, .dateAsc, .sizeAsc:
            return .ascending
        case .nameDesc, .dateDesc, .sizeDesc:
            return .descending
        }
    }
}
