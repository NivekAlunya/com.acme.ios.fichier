//
//  MediaSelectionBottomBar.swift
//  fichier
//

import SwiftUI

/// Floating translucent action bar displayed when multi-selection mode is active in `MediaGridView`.
///
/// Anchored to the bottom of the screen with an ultra-thin material pill shape, providing batch actions:
/// - Favorite / Unfavorite toggle across all selected media items.
/// - Batch export to the iOS Photos library via `PhotoLibrarySaver`.
/// - Batch system share sheet dispatch.
/// - Progress indicator capsule displaying live background download/export status with an optional cancel button.
struct MediaSelectionBottomBar: View {
    /// Number of items currently checked in the selection set.
    let selectedCount: Int
    
    /// Indicates whether all currently selected items are marked as favorites.
    let isAllFavorites: Bool
    
    /// Indicates whether an asynchronous batch operation is actively running.
    let isProcessing: Bool
    
    /// Optional status string displayed inside the progress badge (e.g. "Downloading 2/5...").
    let progressMessage: String?
    
    /// Flag controlling visibility of the "Save to Photos" button (hidden when already in Photos library).
    var showSaveToPhotos: Bool = true
    
    /// Optional closure triggered when the user cancels an ongoing batch operation.
    var onCancel: (() -> Void)? = nil
    
    /// Handler invoked to toggle favorite state across all selected items.
    let onToggleFavorite: () -> Void
    
    /// Handler invoked to save all selected items to the Photos library.
    let onSaveToPhotos: () -> Void
    
    /// Handler invoked to export selected items to the system activity share sheet.
    let onShare: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            if let progressMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                    Text(progressMessage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                    
                    // Interactive cancel button during long batch downloads/exports
                    if let onCancel {
                        Button {
                            onCancel()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.leading, 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Cancel batch operation", comment: "Accessibility label to cancel batch action"))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            HStack(spacing: 24) {
                // 1. Favorite / Unfavorite Button
                Button {
                    onToggleFavorite()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isAllFavorites ? "heart.slash.fill" : "heart.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(selectedCount > 0 ? Color.red : Color.secondary)
                        Text(isAllFavorites ? .Strings.galleryActionUnfavorite : .Strings.galleryActionFavorite)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selectedCount > 0 ? Color.primary : Color.secondary)
                    }
                }
                .disabled(selectedCount == 0 || isProcessing)
                .accessibilityLabel(isAllFavorites ? String(localized: "Remove from Favorites", comment: "Accessibility label to unfavorite selected items") : String(localized: "Add to Favorites", comment: "Accessibility label to favorite selected items"))
                .accessibilityHint(String(localized: "Applies to \(selectedCount) selected items", comment: "Accessibility hint indicating selected count"))
                
                if showSaveToPhotos {
                    Spacer()
                    
                    // 2. Save to Photos Button
                    Button {
                        onSaveToPhotos()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 20))
                            Text(.Strings.galleryActionSaveToPhotos)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(selectedCount > 0 ? Color.primary : Color.secondary)
                        }
                    }
                    .disabled(selectedCount == 0 || isProcessing)
                    .accessibilityLabel(String(localized: "Save to Photos", comment: "Accessibility label to save selected items to Photos"))
                    .accessibilityHint(String(localized: "Downloads and exports \(selectedCount) selected items to your photo library", comment: "Accessibility hint for batch save"))
                }
                
                Spacer()
                
                // 3. Share Button
                Button {
                    onShare()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20))
                            .foregroundStyle(selectedCount > 0 ? Color.blue : Color.secondary)
                        Text(.Strings.galleryActionShare)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selectedCount > 0 ? Color.primary : Color.secondary)
                    }
                }
                .disabled(selectedCount == 0 || isProcessing)
                .accessibilityLabel(String(localized: "Share Items", comment: "Accessibility label to share selected items"))
                .accessibilityHint(String(localized: "Prepares \(selectedCount) selected items for sharing", comment: "Accessibility hint for batch share"))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }
}
