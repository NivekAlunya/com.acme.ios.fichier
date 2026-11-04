//
//  PictureViewerTopBarView.swift
//  fichier
//

import SwiftUI

/// Floating translucent top navigation header for the full-screen photo viewer.
///
/// Displays:
/// - Leading circular dismissal button (`xmark`).
/// - Centered file info capsule displaying file title, current index, total count, and formatted size.
/// - Symmetrical trailing spacer ensuring perfect visual centering regardless of layout bounds.
public struct PictureViewerTopBarView: View {
    /// Active photo media item displayed in the viewer.
    public let item: MediaItem
    
    /// Zero-based index of the photo within the current gallery collection.
    public let currentIndex: Int
    
    /// Total count of photos available in the viewer paging context.
    public let totalCount: Int
    
    /// Callback triggered to dismiss the full-screen photo viewer.
    public let onDismiss: () -> Void
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - item: Active media item.
    ///   - currentIndex: Zero-based photo index.
    ///   - totalCount: Total photo count.
    ///   - onDismiss: Dismissal closure.
    public init(
        item: MediaItem,
        currentIndex: Int,
        totalCount: Int,
        onDismiss: @escaping () -> Void
    ) {
        self.item = item
        self.currentIndex = currentIndex
        self.totalCount = totalCount
        self.onDismiss = onDismiss
    }
    
    /// True when running in an iPad or Mac regular horizontal size class.
    private var isRegular: Bool {
        horizontalSizeClass == .regular
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            closeButton
            
            Spacer(minLength: 8)
            
            fileInfoCapsule
            
            Spacer(minLength: 8)
            
            // Symmetrical invisible counterweight guaranteeing true horizontal centering
            Color.clear
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, isRegular ? 8 : 4)
    }
    
    /// Leading circular close button styled with ultra-thin material and subtle drop shadow.
    private var closeButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Close", comment: "Accessibility label to close photo viewer"))
    }
    
    /// Centered capsule container displaying the photo file name and pagination counter.
    private var fileInfoCapsule: some View {
        HStack(spacing: 6) {
            Text(item.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: isRegular ? 400 : 220)
            
            Text("•")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .fixedSize()
            
            Text(.Strings.commonItemCounterAndSize(currentIndex + 1, totalCount, item.formattedSize))
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        )
    }
}
