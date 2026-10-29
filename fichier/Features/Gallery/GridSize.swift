//
//  GridSize.swift
//  fichier
//

import SwiftUI

enum GridSize: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case medium = "Medium"
    case large = "Large"
    
    var id: String { rawValue }
    
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .compact: return .Strings.galleryGridSizeCompact
        case .medium: return .Strings.galleryGridSizeMedium
        case .large: return .Strings.galleryGridSizeLarge
        }
    }
    
    var minDimension: CGFloat {
        switch self {
        case .compact: return 105
        case .medium: return 155
        case .large: return 240
        }
    }
    
    var thumbnailPixels: CGFloat {
        switch self {
        case .compact: return 200
        case .medium: return 280
        case .large: return 420
        }
    }
    
    var iconName: String {
        switch self {
        case .compact: return "square.grid.4x3.fill"
        case .medium: return "square.grid.2x2"
        case .large: return "rectangle.grid.1x2"
        }
    }
}
