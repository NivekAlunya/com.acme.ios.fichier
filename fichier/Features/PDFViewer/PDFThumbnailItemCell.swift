//
//  PDFThumbnailItemCell.swift
//  fichier
//

#if !os(tvOS)
import SwiftUI
import PDFKit

/// Single thumbnail item view used inside `PDFLeadingThumbnailSidebarView`.
///
/// Features:
/// - Asynchronous thumbnail rendering from `PDFPage.thumbnail(of:for:)` via `.task(id: pageNumber)`.
/// - Rounded rectangular badge displaying the 1-based page number.
/// - Active selection border and glowing accent shadow when the page is currently visible on screen.
public struct PDFThumbnailItemCell: View {
    /// Reference to the underlying PDFKit page object.
    public let page: PDFPage?
    
    /// 1-based page index.
    public let pageNumber: Int
    
    /// Indicates whether this page is currently visible in the active document viewer.
    public let isSelected: Bool
    
    /// Callback triggered when this thumbnail cell is tapped by the user.
    public let onSelect: () -> Void
    
    /// Cached bitmap thumbnail of the page.
    @State private var thumbnail: UIImage?
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - page: PDFKit page reference.
    ///   - pageNumber: 1-based page number.
    ///   - isSelected: Whether page is currently active.
    ///   - onSelect: Tap selection callback.
    public init(
        page: PDFPage?,
        pageNumber: Int,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) {
        self.page = page
        self.pageNumber = pageNumber
        self.isSelected = isSelected
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 54, height: 74)
                    
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 54, maxHeight: 74)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    } else {
                        Color.white.opacity(0.05)
                            .frame(width: 54, height: 74)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? Color.blue : Color.white.opacity(0.2),
                            lineWidth: isSelected ? 2.5 : 0.5
                        )
                )
                .shadow(color: isSelected ? Color.blue.opacity(0.45) : .clear, radius: 4)
                
                Text("\(pageNumber)")
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.blue : Color.clear, in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Page \(pageNumber)", comment: "Thumbnail page accessibility label"))
        .task(id: pageNumber) {
            guard let page else { return }
            let targetSize = CGSize(width: 54, height: 74)
            self.thumbnail = page.thumbnail(of: targetSize, for: .cropBox)
        }
    }
}

#endif // !os(tvOS)
