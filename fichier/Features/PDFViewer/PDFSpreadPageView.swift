//
//  PDFSpreadPageView.swift
//  fichier
//

import SwiftUI
import PDFKit

public struct PDFSpreadPageView: View {
    public let document: PDFDocument
    public let spread: PDFSpread
    public let onTap: () -> Void
    
    public init(document: PDFDocument, spread: PDFSpread, onTap: @escaping () -> Void) {
        self.document = document
        self.spread = spread
        self.onTap = onTap
    }
    
    public var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let isTwoPage = spread.pageIndices.count > 1
            
            HStack(spacing: isTwoPage ? (isLandscape ? 16 : 8) : 0) {
                ForEach(spread.pageIndices, id: \.self) { pageIndex in
                    if let page = document.page(at: pageIndex) {
                        PDFPageCanvasRepresentable(page: page)
                            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
                    }
                }
            }
            .padding(.horizontal, isTwoPage ? 16 : 24)
            .padding(.vertical, 20)
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
        }
    }
}
