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
    
    /// Handler invoked to download selected items and export them to the iOS Files app.
    var onDownloadToFiles: (() -> Void)?
    
    /// Handler invoked to export selected items to the system activity share sheet.
    let onShare: () -> Void
    
    /// Handler invoked to move selected items to another folder.
    var onMove: (() -> Void)?
    
    /// Handler invoked to rename a single selected item.
    var onRename: (() -> Void)?
    
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
                        .accessibilityLabel(Text(.Strings.galleryBatchCancel))
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
                .accessibilityLabel(isAllFavorites ? Text(.Strings.galleryActionRemoveFromFavorites) : Text(.Strings.galleryActionAddToFavorites))
                .accessibilityHint(Text(.Strings.galleryBatchSelectionAppliesCount(selectedCount)))
                
                // 2. Download Options (Save to Photos & Download to Files)
                Menu {
                    if showSaveToPhotos {
                        Button {
                            onSaveToPhotos()
                        } label: {
                            Label(
                                .Strings.galleryActionSaveToPhotos,
                                systemImage: "photo"
                            )
                        }
                    }
                    if let onDownloadToFiles {
                        Button {
                            onDownloadToFiles()
                        } label: {
                            Label(
                                .Strings.galleryActionDownloadToFiles,
                                systemImage: "arrow.down.doc"
                            )
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selectedCount > 0 ? Color.primary : Color.secondary)
                        .frame(width: 28, height: 28)
                }
                .disabled(selectedCount == 0 || isProcessing)
                .accessibilityLabel(.Strings.galleryActionDownloadOptionsAccessibility)
                
                if showFileManagement {
                    // 3. Rename Button (for single selected item)
                    if selectedCount == 1, let onRename {
                        Button {
                            onRename()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .disabled(isProcessing)
                        .accessibilityLabel(.Strings.galleryActionRenameAccessibility)
                        .accessibilityHint(.Strings.galleryActionRenameHint)
                    }
                    
                    // 4. Move Button
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
                    .accessibilityLabel(Text(.Strings.galleryActionMoveItems))
                    .accessibilityHint(Text(.Strings.galleryBatchMoveHint(selectedCount)))
                    
                    // 5. Delete / Trash Button
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
                    .accessibilityLabel(Text(.Strings.galleryActionDeleteItems))
                    .accessibilityHint(Text(.Strings.galleryBatchDeleteHint(selectedCount)))
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
                .accessibilityLabel(Text(.Strings.galleryActionShareItems))
                .accessibilityHint(Text(.Strings.galleryBatchShareHint(selectedCount)))
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
