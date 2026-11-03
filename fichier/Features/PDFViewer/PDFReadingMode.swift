//
//  PDFReadingMode.swift
//  fichier
//

import Foundation

public enum PDFReadingMode: String, CaseIterable, Identifiable, Sendable {
    case continuous = "continuous"
    case book = "book"
    case twoUp = "twoUp"
    
    public var id: String { rawValue }
    
    public var isBookMode: Bool {
        self != .continuous
    }
    
    public var displaysAsBook: Bool {
        self == .book
    }
    
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
