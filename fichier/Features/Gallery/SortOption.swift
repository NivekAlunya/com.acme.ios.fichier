//
//  SortOption.swift
//  fichier
//

import Foundation

/// Defines criteria and ordering directions for sorting gallery media items.
enum SortOption: String, CaseIterable, Identifiable {
    /// Alphabetical order by file name (A through Z).
    case nameAsc = "Name (A–Z)"
    
    /// Reverse alphabetical order by file name (Z through A).
    case nameDesc = "Name (Z–A)"
    
    /// Chronological order by modification date, newest files first.
    case dateDesc = "Date (Newest First)"
    
    /// Chronological order by modification date, oldest files first.
    case dateAsc = "Date (Oldest First)"
    
    /// Descending order by file size in bytes, largest items first.
    case sizeDesc = "Size (Largest First)"
    
    /// Ascending order by file size in bytes, smallest items first.
    case sizeAsc = "Size (Smallest First)"
    
    /// Grouped by media category: Images first, then Videos, then Documents and PDFs.
    case kindAsc = "Kind (Images, Videos, PDFs)"
    
    /// Grouped by media category: Documents and PDFs first, then Videos, then Images.
    case kindDesc = "Kind (PDFs, Videos, Images)"
    
    /// Descending order by total pixel resolution (highest resolution first).
    case resolutionDesc = "Resolution (Highest First)"
    
    /// Ascending order by total pixel resolution (lowest resolution first).
    case resolutionAsc = "Resolution (Lowest First)"
    
    /// Descending order by playback duration (longest videos first).
    case durationDesc = "Duration (Longest First)"
    
    /// Ascending order by playback duration (shortest videos first).
    case durationAsc = "Duration (Shortest First)"
    
    /// Stable string identifier for `Identifiable` conformance.
    var id: String { rawValue }
    
    /// Localized string resource representing the sort option in gallery menus.
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .nameAsc: return .Strings.gallerySortNameAscending
        case .nameDesc: return .Strings.gallerySortNameDescending
        case .dateDesc: return .Strings.gallerySortDateNewest
        case .dateAsc: return .Strings.gallerySortDateOldest
        case .sizeDesc: return .Strings.gallerySortSizeLargest
        case .sizeAsc: return .Strings.gallerySortSizeSmallest
        case .kindAsc: return .Strings.gallerySortKindAscending
        case .kindDesc: return .Strings.gallerySortKindDescending
        case .resolutionDesc: return .Strings.gallerySortResolutionHighest
        case .resolutionAsc: return .Strings.gallerySortResolutionLowest
        case .durationDesc: return .Strings.gallerySortDurationLongest
        case .durationAsc: return .Strings.gallerySortDurationShortest
        }
    }
    
    /// SF Symbol icon name representing the sort criterion in menus.
    var iconName: String {
        switch self {
        case .nameAsc, .nameDesc: return "textformat.abc"
        case .dateDesc, .dateAsc: return "calendar"
        case .sizeDesc, .sizeAsc: return "arrow.up.arrow.down.circle"
        case .kindAsc, .kindDesc: return "square.stack.3d.up"
        case .resolutionDesc, .resolutionAsc: return "viewfinder"
        case .durationDesc, .durationAsc: return "clock"
        }
    }
}
