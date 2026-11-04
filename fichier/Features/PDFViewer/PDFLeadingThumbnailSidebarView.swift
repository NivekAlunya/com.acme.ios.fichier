//
//  PDFLeadingThumbnailSidebarView.swift
//  fichier
//

import SwiftUI
import PDFKit

/// Floating vertical thumbnail sidebar docked on the leading edge of `PDFDetailView`.
///
/// Features:
/// - Vertical scrollable list of all document pages rendered via `PDFThumbnailItemCell`.
/// - Automatic synchronization with `ScrollViewReader` scrolling the active page into center focus.
/// - Multi-page selection highlighting supporting both single-page continuous and two-page book spreads.
/// - Haptic selection feedback (`UISelectionFeedbackGenerator`) upon tapping a page thumbnail.
public struct PDFLeadingThumbnailSidebarView: View {
    /// Active PDFKit document instance.
    public let document: PDFDocument
    
    /// 1-based index of the first currently visible page.
    public let currentPage: Int
    
    /// 1-based index of the last currently visible page (equals `currentPage` in single page mode).
    public let endVisiblePage: Int
    
    /// Action callback triggered when the user taps a thumbnail to navigate.
    public let onPageSelected: (Int) -> Void
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - document: Underlying PDFKit document.
    ///   - currentPage: 1-based starting visible page.
    ///   - endVisiblePage: 1-based ending visible page.
    ///   - onPageSelected: Selection callback.
    public init(
        document: PDFDocument,
        currentPage: Int,
        endVisiblePage: Int,
        onPageSelected: @escaping (Int) -> Void
    ) {
        self.document = document
        self.currentPage = currentPage
        self.endVisiblePage = endVisiblePage
        self.onPageSelected = onPageSelected
    }
    
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        let pageNumber = index + 1
                        let isSelected = pageNumber >= currentPage && pageNumber <= endVisiblePage
                        
                        PDFThumbnailItemCell(
                            page: document.page(at: index),
                            pageNumber: pageNumber,
                            isSelected: isSelected,
                            onSelect: {
                                let generator = UISelectionFeedbackGenerator()
                                generator.selectionChanged()
                                onPageSelected(pageNumber)
                            }
                        )
                        .id(pageNumber)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
            }
            .frame(width: 72)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 8, x: 2, y: 2)
            .onAppear {
                proxy.scrollTo(currentPage, anchor: .center)
            }
            .onChange(of: currentPage) { _, newPage in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newPage, anchor: .center)
                }
            }
        }
    }
}
