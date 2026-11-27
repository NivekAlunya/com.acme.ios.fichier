//
//  GridSize.swift
//  fichier
//

import SwiftUI
import FichierKit

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
    
    /// Canonical master pixel dimension shared across all grid densities.
    var thumbnailPixels: CGFloat {
        MediaCacheManager.standardThumbnailDimension
    }
    
    /// SF Symbol icon name representing this grid density in toolbar menus.
    var iconName: String {
        switch self {
        case .compact: return "square.grid.4x3.fill"
        case .medium: return "square.grid.2x2"
        case .large: return "rectangle.grid.1x2"
        }
    }
    
    /// Title font point size on media item cells for this grid density.
    var titleFontSize: CGFloat {
        switch self {
        case .compact: return 11
        case .medium: return 13
        case .large: return 16
        }
    }
    
    /// Secondary metadata and format font point size for this grid density.
    var detailFontSize: CGFloat {
        switch self {
        case .compact: return 9
        case .medium: return 11
        case .large: return 13
        }
    }
    
    /// Title Dynamic Type font on media item cells for this grid density.
    var titleFont: Font {
        switch self {
        case .compact: return .caption.weight(.semibold)
        case .medium: return .subheadline.weight(.semibold)
        case .large: return .headline
        }
    }
    
    /// Secondary metadata Dynamic Type font for this grid density.
    var detailFont: Font {
        switch self {
        case .compact: return .caption2
        case .medium: return .caption
        case .large: return .subheadline
        }
    }
    
    /// Capsule format badge Dynamic Type font for this grid density.
    var capsuleFont: Font {
        switch self {
        case .compact: return .caption2.weight(.bold)
        case .medium: return .caption2.weight(.bold)
        case .large: return .caption.weight(.bold)
        }
    }
    
    /// Icon Dynamic Type font for badges and indicators.
    var iconFont: Font {
        switch self {
        case .compact: return .caption2.weight(.bold)
        case .medium: return .caption2.weight(.bold)
        case .large: return .caption.weight(.bold)
        }
    }
    
    /// Centered format SF Symbol pictogram Dynamic Type font.
    var pictogramFont: Font {
        switch self {
        case .compact: return .title3.weight(.medium)
        case .medium: return .title2.weight(.medium)
        case .large: return .title.weight(.semibold)
        }
    }
    
    /// Diameter of the centered media format indicator circle badge.
    var pictogramBadgeSize: CGFloat {
        switch self {
        case .compact: return 32
        case .medium: return 38
        case .large: return 48
        }
    }
    
    /// Font point size of the centered format SF Symbol pictogram.
    var pictogramIconSize: CGFloat {
        switch self {
        case .compact: return 14
        case .medium: return 16
        case .large: return 22
        }
    }
}
