//
//  PDFSpread.swift
//  fichier
//

import Foundation

public struct PDFSpread: Identifiable, Hashable, Sendable {
    public let id: Int
    public let pageIndices: [Int]
    
    public init(id: Int, pageIndices: [Int]) {
        self.id = id
        self.pageIndices = pageIndices
    }
    
    public var firstPageNumber: Int {
        (pageIndices.first ?? 0) + 1
    }
    
    public var lastPageNumber: Int {
        (pageIndices.last ?? 0) + 1
    }
    
    public var displayText: String {
        if pageIndices.count == 1 {
            return "Page \(firstPageNumber)"
        } else if pageIndices.count >= 2 {
            return "Pages \(firstPageNumber)–\(lastPageNumber)"
        }
        return ""
    }
    
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
