//
//  MediaFilter.swift
//  fichier
//

import Foundation

enum MediaFilter: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case all = "All"
    case photos = "Photos"
    case videos = "Videos"
    
    var iconName: String {
        switch self {
        case .all: return "photo.on.rectangle.angled"
        case .photos: return "photo"
        case .videos: return "video"
        }
    }
}
