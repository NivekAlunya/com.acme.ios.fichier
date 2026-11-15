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
    
    /// Flag controlling visibility of file management buttons (Move, Delete).
    var showFileManagement: Bool = false
    
    /// Optional closure triggered when the user cancels an ongoing batch operation.
    var onCancel: (() -> Void)?
    
    /// Handler invoked to toggle favorite state across all selected items.
    let onToggleFavorite: () -> Void
    
    /// Handler invoked to save all selected items to the Photos library.
    let onSaveToPhotos: () -> Void
    
    /// Handler invoked to export selected items to the system activity share sheet.
    let onShare: () -> Void
    
    /// Handler invoked to move selected items to another folder.
    var onMove: (() -> Void)?
    
    /// Handler invoked to delete (trash) selected items.
    var onDelete: (() -> Void)?
    
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
            
            HStack(spacing: 10) {
                // 1. Favorite / Unfavorite Button
                Button {
                    onToggleFavorite()
                } label: {
                    Image(systemName: isAllFavorites ? "heart.slash.fill" : "heart.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isAllFavorites ? Color.red : (selectedCount > 0 ? Color.red : Color.secondary))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0 || isProcessing)
                .accessibilityLabel(isAllFavorites ? String(localized: "Remove from Favorites", comment: "Accessibility label to unfavorite selected items") : String(localized: "Add to Favorites", comment: "Accessibility label to favorite selected items"))
                .accessibilityHint(String(localized: "Applies to \(selectedCount) selected items", comment: "Accessibility hint indicating selected count"))
                
                if showSaveToPhotos {
                    // 2. Save to Photos Button
                    Button {
                        onSaveToPhotos()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(selectedCount > 0 ? Color.primary : Color.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCount == 0 || isProcessing)
                    .accessibilityLabel(String(localized: "Save to Photos", comment: "Accessibility label to save selected items to Photos"))
                    .accessibilityHint(String(localized: "Downloads and exports \(selectedCount) selected items to your photo library", comment: "Accessibility hint for batch save"))
                }
                
                if showFileManagement {
                    // 3. Move Button
                    Button {
                        onMove?()
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(selectedCount > 0 ? Color.accentColor : Color.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCount == 0 || isProcessing)
                    .accessibilityLabel(String(localized: "Move Items", comment: "Accessibility label to move selected items"))
                    .accessibilityHint(String(localized: "Moves \(selectedCount) selected items to another folder", comment: "Accessibility hint for batch move"))
                    
                    // 4. Delete / Trash Button
                    Button {
                        onDelete?()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(selectedCount > 0 ? Color.red : Color.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCount == 0 || isProcessing)
                    .accessibilityLabel(String(localized: "Delete Items", comment: "Accessibility label to delete selected items"))
                    .accessibilityHint(String(localized: "Moves \(selectedCount) selected items to the trash", comment: "Accessibility hint for batch delete"))
                }
                
                // 5. Share Button
                Button {
                    onShare()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selectedCount > 0 ? Color.blue : Color.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0 || isProcessing)
                .accessibilityLabel(String(localized: "Share Items", comment: "Accessibility label to share selected items"))
                .accessibilityHint(String(localized: "Prepares \(selectedCount) selected items for sharing", comment: "Accessibility hint for batch share"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
            )
            .padding(.bottom, 10)
        }
    }
}
