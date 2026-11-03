//
//  PDFLeadingThumbnailSidebarView.swift
//  fichier
//

import SwiftUI
import PDFKit

public struct PDFLeadingThumbnailSidebarView: View {
    public let document: PDFDocument
    public let currentPage: Int
    public let endVisiblePage: Int
    public let onPageSelected: (Int) -> Void
    
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
