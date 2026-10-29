//
//  SortOption.swift
//  fichier
//

import Foundation

enum SortOption: String, CaseIterable, Identifiable {
    case nameAsc = "Name (A–Z)"
    case nameDesc = "Name (Z–A)"
    case dateDesc = "Date (Newest First)"
    case dateAsc = "Date (Oldest First)"
    case sizeDesc = "Size (Largest First)"
    case sizeAsc = "Size (Smallest First)"
    
    var id: String { rawValue }
    
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .nameAsc: return .Strings.gallerySortNameAscending
        case .nameDesc: return .Strings.gallerySortNameDescending
        case .dateDesc: return .Strings.gallerySortDateNewest
        case .dateAsc: return .Strings.gallerySortDateOldest
        case .sizeDesc: return .Strings.gallerySortSizeLargest
        case .sizeAsc: return .Strings.gallerySortSizeSmallest
        }
    }
    
    var iconName: String {
        switch self {
        case .nameAsc, .nameDesc: return "textformat.abc"
        case .dateDesc, .dateAsc: return "calendar"
        case .sizeDesc, .sizeAsc: return "arrow.up.arrow.down.circle"
        }
    }
}
