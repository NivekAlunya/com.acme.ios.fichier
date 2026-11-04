//
//  ViewMode.swift
//  fichier
//

import Foundation

/// Defines visual presentation layout options for media gallery items.
enum ViewMode: String, CaseIterable, Identifiable {
    /// Adaptive multi-column thumbnail grid (`LazyVGrid`).
    case grid = "Grid"
    
    /// Single-column vertical list detailing metadata, file sizes, and dates (`LazyVStack`).
    case list = "List"
    
    /// Stable string identifier for `Identifiable` conformance.
    var id: String { rawValue }
    
    /// Localized string resource representing the display name in toolbar menus.
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .grid: return .Strings.galleryViewModeGrid
        case .list: return .Strings.galleryViewModeList
        }
    }
    
    /// System SF Symbol name for the selection mode toggle button matching this layout mode.
    var selectionIconName: String {
        switch self {
        case .list: return "checklist"
        case .grid: return "circle.grid.2x2.topleft.checkmark.filled"
        }
    }
}
