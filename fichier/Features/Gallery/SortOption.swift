//
//  SortOption.swift
//  fichier
//

import Foundation

enum SortOption: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case nameAsc = "Name (A–Z)"
    case nameDesc = "Name (Z–A)"
    case dateDesc = "Date (Newest First)"
    case dateAsc = "Date (Oldest First)"
    case sizeDesc = "Size (Largest First)"
    case sizeAsc = "Size (Smallest First)"
    
    var iconName: String {
        switch self {
        case .nameAsc: return "arrow.up"
        case .nameDesc: return "arrow.down"
        case .dateDesc: return "calendar.badge.clock"
        case .dateAsc: return "calendar"
        case .sizeDesc: return "arrow.down.circle"
        case .sizeAsc: return "arrow.up.circle"
        }
    }
}
