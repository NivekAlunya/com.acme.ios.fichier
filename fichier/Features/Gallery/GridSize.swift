//
//  GridSize.swift
//  fichier
//

import Foundation

enum GridSize: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case compact = "Compact"
    case medium = "Medium"
    case large = "Large"
    
    var iconName: String {
        switch self {
        case .compact: return "square.grid.3x3"
        case .medium: return "square.grid.2x2"
        case .large: return "rectangle.grid.1x2"
        }
    }
    
    var minDimension: CGFloat {
        switch self {
        case .compact: return 85
        case .medium: return 120
        case .large: return 180
        }
    }
    
    var thumbnailPixels: CGFloat {
        switch self {
        case .compact: return 180
        case .medium: return 260
        case .large: return 420
        }
    }
}
