//
//  MediaSelectionBottomBar.swift
//  fichier
//

import SwiftUI

struct MediaSelectionBottomBar: View {
    let selectedCount: Int
    let isAllFavorites: Bool
    let isProcessing: Bool
    let progressMessage: String?
    var showSaveToPhotos: Bool = true
    let onToggleFavorite: () -> Void
    let onSaveToPhotos: () -> Void
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
                
                if showSaveToPhotos {
                    Spacer()
                    
                    // 2. Save to Photos Button
                    Button {
                        onSaveToPhotos()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 20))
                                .foregroundStyle(selectedCount > 0 ? Color.blue : Color.secondary)
                            Text(.Strings.galleryActionSaveToPhotos)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(selectedCount > 0 ? Color.primary : Color.secondary)
                        }
                    }
                    .disabled(selectedCount == 0 || isProcessing)
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
