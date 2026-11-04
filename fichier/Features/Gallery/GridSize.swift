//
//  GridSize.swift
//  fichier
//

import SwiftUI

/// Preset grid density sizing options for displaying media in `MediaGridView`.
///
/// Configures column counts, minimum cell width bounds, and thumbnail decoding dimensions:
/// - `.compact`: Dense layout suited for browsing vast libraries rapidly.
/// - `.medium`: Balanced default providing thumbnail detail and high information density.
/// - `.large`: Expansive layout highlighting high-resolution media details.
enum GridSize: String, CaseIterable, Identifiable {
    /// Dense thumbnail grid with 4+ columns on tablets and 3+ on phones.
    case compact = "Compact"
    
    /// Standard balanced grid layout.
    case medium = "Medium"
    
    /// Large preview grid with 1-2 columns displaying rich detail.
    case large = "Large"
    
    /// Stable string identifier for `Identifiable` conformance.
    var id: String { rawValue }
    
    /// Localized string resource representing the display name in menu options.
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .compact: return .Strings.galleryGridSizeCompact
        case .medium: return .Strings.galleryGridSizeMedium
        case .large: return .Strings.galleryGridSizeLarge
        }
    }
    
    /// Minimum point dimension passed to `GridItem(.adaptive(minimum:))` for SwiftUI column sizing.
    var minDimension: CGFloat {
        switch self {
        case .compact: return 105
        case .medium: return 155
        case .large: return 240
        }
    }
    
    /// Target pixel width/height requested from downsampling decoders to optimize RAM allocation.
    var thumbnailPixels: CGFloat {
        switch self {
        case .compact: return 200
        case .medium: return 280
        case .large: return MediaCacheManager.standardThumbnailDimension
        }
    }
    
    /// SF Symbol icon name representing this grid density in toolbar menus.
    var iconName: String {
        switch self {
        case .compact: return "square.grid.4x3.fill"
        case .medium: return "square.grid.2x2"
        case .large: return "rectangle.grid.1x2"
        }
    }
}
