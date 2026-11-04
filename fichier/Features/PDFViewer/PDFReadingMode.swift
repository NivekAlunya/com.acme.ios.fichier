//
//  PDFReadingMode.swift
//  fichier
//

import Foundation

/// Reading layout configurations available when displaying documents in `PDFDetailView`.
///
/// Controls page layout and pagination behavior:
/// - `.continuous`: Vertical single-page continuous scrolling using native `PDFView`.
/// - `.book`: Two pages side-by-side with Page 1 treated as an isolated right-hand cover.
/// - `.twoUp`: Two pages side-by-side starting immediately with Pages 1 and 2 paired.
public enum PDFReadingMode: String, CaseIterable, Identifiable, Sendable {
    /// Vertical scrolling single page reading experience.
    case continuous
    
    /// Traditional book spread with a standalone cover page followed by facing page pairs.
    case book
    
    /// Side-by-side spread pairing pages without a standalone cover.
    case twoUp
    
    /// Stable string identifier for `Identifiable` conformance.
    public var id: String { rawValue }
    
    /// Indicates whether this reading mode utilizes horizontal spread paging rather than vertical scrolling.
    public var isBookMode: Bool {
        self != .continuous
    }
    
    /// Indicates whether Page 1 is treated as an isolated book cover spread.
    public var displaysAsBook: Bool {
        self == .book
    }
    
    /// Localized title describing the reading mode for user interface menus.
    public var localizedTitle: String {
        switch self {
        case .continuous:
            return String(localized: "Single Page", comment: "Single page continuous scroll reading mode")
        case .book:
            return String(localized: "Book View (With Cover)", comment: "Two pages side-by-side with cover page")
        case .twoUp:
            return String(localized: "Two Pages (No Cover)", comment: "Two pages side-by-side without cover page")
        }
    }
    
    /// SF Symbol icon name representing the reading mode in picker buttons.
    public var iconName: String {
        switch self {
        case .continuous:
            return "doc.text"
        case .book:
            return "book"
        case .twoUp:
            return "rectangle.split.2x1"
        }
    }
}
