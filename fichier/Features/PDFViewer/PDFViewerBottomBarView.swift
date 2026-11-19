//
//  PDFViewerBottomBarView.swift
//  fichier
//

#if !os(tvOS)
import SwiftUI

/// Floating translucent action toolbar docked at the bottom of the full-screen PDF viewer.
///
/// Follows the design language of `PictureViewerBottomBarView`:
/// - Leading and Trailing chevron buttons (`chevron.left` / `chevron.right`) to navigate previous and next documents.
/// - Centered reading mode menu/toggle (Continuous vs Book mode).
/// - Translucent page indicator pill ("Page X of Y" or "Pages X–Y of Z").
/// - Favorite state toggle button.
/// - Native SwiftUI `ShareLink` export.
public struct PDFViewerBottomBarView: View {
    /// Indicates whether the collection contains more than one document, enabling navigation chevrons.
    public let hasMultipleDocuments: Bool
    
    /// Two-way binding for user reading mode (continuous single page vs book spread).
    @Binding public var readingMode: PDFReadingMode
    
    /// Formatted status string displaying active page numbers (e.g. "Page 1 of 40").
    public let pageInfoText: String
    
    /// Indicates whether the current document is marked as a favorite.
    public let isFavorite: Bool
    
    /// Local file URL for the cached or downloaded document, enabling ShareLink.
    public let localFileURL: URL?
    
    /// Display name of the active document.
    public let currentName: String
    
    /// Action handler to navigate to the previous document.
    public let onPreviousDocument: () -> Void
    
    /// Action handler to navigate to the next document.
    public let onNextDocument: () -> Void
    
    /// Action handler to toggle favorite status.
    public let onToggleFavorite: () -> Void
    
    /// Memberwise designated initializer.
    public init(
        hasMultipleDocuments: Bool,
        readingMode: Binding<PDFReadingMode>,
        pageInfoText: String,
        isFavorite: Bool,
        localFileURL: URL?,
        currentName: String,
        onPreviousDocument: @escaping () -> Void,
        onNextDocument: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void
    ) {
        self.hasMultipleDocuments = hasMultipleDocuments
        self._readingMode = readingMode
        self.pageInfoText = pageInfoText
        self.isFavorite = isFavorite
        self.localFileURL = localFileURL
        self.currentName = currentName
        self.onPreviousDocument = onPreviousDocument
        self.onNextDocument = onNextDocument
        self.onToggleFavorite = onToggleFavorite
    }
    
    private var isBookMode: Bool {
        readingMode.isBookMode
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // Leading: Previous Document Button
            Button {
                onPreviousDocument()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(hasMultipleDocuments ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 32, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasMultipleDocuments)
            .accessibilityLabel(Text(.Strings.pdfActionPreviousDocument))
            
            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.3))
            
            // Middle: Controls & Status
            HStack(spacing: 10) {
                // 1. Reading Mode (Continuous / Book mode)
                Menu {
                    ForEach(PDFReadingMode.allCases) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                readingMode = mode
                            }
                        } label: {
                            Label(
                                mode.localizedTitle,
                                systemImage: readingMode == mode ? "checkmark" : mode.iconName
                            )
                        }
                    }
                } label: {
                    Image(systemName: isBookMode ? "book.fill" : "book")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isBookMode ? Color.blue : Color.white)
                        .frame(width: 28, height: 28)
                } primaryAction: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        readingMode = isBookMode ? .continuous : .book
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isBookMode ? Text(.Strings.pdfSwitchSinglePage) : Text(.Strings.pdfSwitchBookView))
                
                // 2. Page Counter Pill
                Text(pageInfoText)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
                    .accessibilityLabel(pageInfoText)
                
                // 3. Favorite Button
                Button {
                    onToggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isFavorite ? Color.red : Color.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? Text(.Strings.galleryActionRemoveFromFavorites) : Text(.Strings.galleryActionAddToFavorites))
                
                // 4. Share Document
                if let localFileURL {
                    ShareLink(item: localFileURL, preview: SharePreview(currentName)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(.Strings.pdfActionShareDocument))
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 4)
            
            // Trailing: Next Document Button
            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.3))
            
            Button {
                onNextDocument()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(hasMultipleDocuments ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 32, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasMultipleDocuments)
            .accessibilityLabel(Text(.Strings.pdfActionNextDocument))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
        )
    }
}
#endif
