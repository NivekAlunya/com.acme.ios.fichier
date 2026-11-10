//
//  PDFSpread.swift
//  fichier
//

#if !os(tvOS)
import Foundation

/// Value model representing a discrete page spread displayed together in horizontal book mode.
///
/// Encapsulates:
/// - One page (e.g. cover page or trailing single page at the end of an odd-numbered document).
/// - Two facing pages (e.g. left and right pages of an open book).
nonisolated public struct PDFSpread: Identifiable, Hashable, Sendable {
    /// Zero-based spread index within the active document collection.
    public let id: Int
    
    /// Array of zero-based document page indices displayed within this spread.
    public let pageIndices: [Int]
    
    /// Memberwise designated initializer.
    ///
    /// - Parameters:
    ///   - id: Unique spread identifier.
    ///   - pageIndices: Zero-based page indices included in this spread.
    public init(id: Int, pageIndices: [Int]) {
        self.id = id
        self.pageIndices = pageIndices
    }
    
    /// 1-based index of the first page appearing in this spread.
    public var firstPageNumber: Int {
        (pageIndices.first ?? 0) + 1
    }
    
    /// 1-based index of the last page appearing in this spread.
    public var lastPageNumber: Int {
        (pageIndices.last ?? 0) + 1
    }
    
    /// Formatted user-facing display string (e.g. "Page 1" or "Pages 2–3").
    public var displayText: String {
        if pageIndices.count == 1 {
            return "Page \(firstPageNumber)"
        } else if pageIndices.count >= 2 {
            return "Pages \(firstPageNumber)–\(lastPageNumber)"
        }
        return ""
    }
    
    /// Synthesizes an array of `PDFSpread` items partitioning a document's pages.
    ///
    /// When `displaysAsBook` is `true`:
    /// - Spread 0 holds Page 0 alone (the cover).
    /// - Subsequent pages are paired (1–2, 3–4, etc.).
    /// When `displaysAsBook` is `false`:
    /// - Pages are paired immediately from the start (0–1, 2–3, etc.).
    ///
    /// - Parameters:
    ///   - pageCount: Total number of pages in the PDF document.
    ///   - displaysAsBook: Whether Page 0 is isolated as a standalone cover.
    /// - Returns: Ordered array of partitioned `PDFSpread` values.
    public static func buildSpreads(pageCount: Int, displaysAsBook: Bool) -> [PDFSpread] {
        guard pageCount > 0 else { return [] }
        var result: [PDFSpread] = []
        var nextId = 0
        var currentIndex = 0
        
        if displaysAsBook {
            result.append(PDFSpread(id: nextId, pageIndices: [0]))
            nextId += 1
            currentIndex = 1
        }
        
        while currentIndex < pageCount {
            if currentIndex + 1 < pageCount {
                result.append(PDFSpread(id: nextId, pageIndices: [currentIndex, currentIndex + 1]))
                nextId += 1
                currentIndex += 2
            } else {
                result.append(PDFSpread(id: nextId, pageIndices: [currentIndex]))
                nextId += 1
                currentIndex += 1
            }
        }
        
        return result
    }
}

#endif // !os(tvOS)
