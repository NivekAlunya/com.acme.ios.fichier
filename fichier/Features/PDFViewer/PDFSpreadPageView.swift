//
//  PDFSpreadPageView.swift
//  fichier
//

import SwiftUI
import PDFKit

/// Renders a single spread (one or two facing pages) within `PDFDetailView`'s book mode `TabView`.
///
/// Lays out pages side-by-side using `PDFPageCanvasRepresentable`, applying realistic drop shadows,
/// adaptive horizontal spacing for landscape orientations, and tap gesture detection to toggle HUD controls.
public struct PDFSpreadPageView: View {
    /// Reference to the active `PDFDocument`.
    public let document: PDFDocument
    
    /// Target spread descriptor containing page indices for this view.
    public let spread: PDFSpread
    
    /// Action callback triggered when the user taps anywhere on the spread canvas.
    public let onTap: () -> Void
    
    /// Memberwise designated initializer.
    ///
    /// - Parameters:
    ///   - document: Underlying PDFKit document.
    ///   - spread: Spread descriptor.
    ///   - onTap: Tap gesture handler.
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
