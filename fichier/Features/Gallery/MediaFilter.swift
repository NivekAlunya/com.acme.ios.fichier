//
//  MediaFilter.swift
//  fichier
//

import Foundation

enum MediaFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case photos = "Photos"
    case videos = "Videos"
    case documents = "Documents"
    
    var id: String { rawValue }
    
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .all: return .Strings.galleryFilterAll
        case .photos: return .Strings.galleryFilterPhotos
        case .videos: return .Strings.galleryFilterVideos
        case .documents: return LocalizedStringResource("Documents", defaultValue: "Documents")
        }
    }
    
    var iconName: String {
        switch self {
        case .all: return "photo.on.rectangle.angled"
        case .photos: return "photo"
        case .videos: return "video"
        case .documents: return "doc.text.fill"
        }
    }
}
