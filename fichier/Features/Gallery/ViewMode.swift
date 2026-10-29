//
//  ViewMode.swift
//  fichier
//

import Foundation

enum ViewMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case list = "List"
    var id: String { rawValue }
    
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .grid: return .Strings.galleryViewModeGrid
        case .list: return .Strings.galleryViewModeList
        }
    }
}
