//
//  PictureViewerTopBarView.swift
//  fichier
//

import SwiftUI

public struct PictureViewerTopBarView: View {
    public let item: MediaItem
    public let currentIndex: Int
    public let totalCount: Int
    public let onDismiss: () -> Void
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
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
