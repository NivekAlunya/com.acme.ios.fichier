//
//  PictureViewerTopBarView.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Floating translucent top navigation header for the full-screen photo viewer.
///
/// Displays:
/// - Leading circular dismissal button (`xmark`).
/// - Centered 2-line file info container displaying file name on the first line,
///   and playlist counter, formatted size, and image frame dimensions on the second line.
/// - Symmetrical trailing spacer ensuring perfect visual centering regardless of layout bounds.
public struct PictureViewerTopBarView: View {
    /// Active photo media item displayed in the viewer.
    public let item: MediaItem
    
    /// Zero-based index of the photo within the current gallery collection.
    public let currentIndex: Int
    
    /// Total count of photos available in the viewer paging context.
    public let totalCount: Int

    /// Optional explicit image frame dimensions (e.g. "3840 × 2160").
    public let frameSize: String?
    
    /// Callback triggered to dismiss the full-screen photo viewer.
    public let onDismiss: () -> Void
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var resolvedFrameSize: String?
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - item: Active media item.
    ///   - currentIndex: Zero-based photo index.
    ///   - totalCount: Total photo count.
    ///   - frameSize: Optional frame size descriptor.
    ///   - onDismiss: Dismissal closure.
    public init(
        item: MediaItem,
        currentIndex: Int,
        totalCount: Int,
        frameSize: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.item = item
        self.currentIndex = currentIndex
        self.totalCount = totalCount
        self.frameSize = frameSize
        self.onDismiss = onDismiss
    }
    
    /// True when running in an iPad or Mac regular horizontal size class.
    private var isRegular: Bool {
        horizontalSizeClass == .regular
    }

    /// Effective dimensions taking passed explicit override or background resolved cache.
    private var effectiveDimensions: String? {
        if let frameSize, !frameSize.isEmpty {
            return frameSize
        }
        return resolvedFrameSize
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            closeButton
            
            Spacer(minLength: 8)
            
            fileInfoContainer
            
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
    
    /// Centered container presenting the image name on the first line and
    /// counter, size, and frame dimensions on the second line.
    private var fileInfoContainer: some View {
        VStack(spacing: 2) {
            // Line 1: image name
            Text(item.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: isRegular ? 450 : 250)
            
            // Line 2: rest of the information
            HStack(spacing: 6) {
                Text(.Strings.commonItemCounterAndSize(currentIndex + 1, totalCount, item.formattedSize))
                
                if let dimensions = effectiveDimensions {
                    Text("•")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                        .fixedSize()
                    
                    Text(dimensions)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.75))
            .lineLimit(1)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        )
        .task(id: item.id) {
            if let cached = MediaDetailStore.shared.cachedDetail(for: item.id) {
                resolvedFrameSize = cached
            } else if frameSize == nil {
                resolvedFrameSize = await MediaDetailStore.shared.resolveDetail(for: item.asMediaSourceItem)
            }
        }
    }
}
