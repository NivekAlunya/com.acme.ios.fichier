//
//  MediaFilter.swift
//  fichier
//

import Foundation

/// Filter category restricting visible gallery contents to specific media types.
enum MediaFilter: String, CaseIterable, Identifiable {
    /// Displays all discovered media items (photos, videos, documents).
    case all = "All"
    
    /// Displays still images, animated GIFs, and RAW camera captures.
    case photos = "Photos"
    
    /// Displays playable video files.
    case videos = "Videos"
    
    /// Displays PDF document files.
    case documents = "Documents"
    
    /// Stable string identifier for `Identifiable` conformance.
    var id: String { rawValue }
    
    /// Localized string resource representing the filter name in gallery pickers.
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .all: return .Strings.galleryFilterAll
        case .photos: return .Strings.galleryFilterPhotos
        case .videos: return .Strings.galleryFilterVideos
        case .documents: return LocalizedStringResource("Documents", defaultValue: "Documents")
        }
    }
    
    /// SF Symbol icon name representing the filter in segment selectors.
    var iconName: String {
        switch self {
        case .all: return "photo.on.rectangle.angled"
        case .photos: return "photo"
        case .videos: return "video"
        case .documents: return "doc.text.fill"
        }
    }
}
