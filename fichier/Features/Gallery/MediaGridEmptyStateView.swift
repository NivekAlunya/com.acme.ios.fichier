//
//  MediaGridEmptyStateView.swift
//  fichier
//

import SwiftUI

/// View rendering loading, error, and empty state representations for the media gallery.
@MainActor
struct MediaGridEmptyStateView: View {
    let isLoading: Bool
    let errorMessage: String?
    let searchText: String
    let selectedFolderName: String?
    let hasSelectedFolder: Bool
    let parentFolderName: String?
    let onRetry: () -> Void
    let onNavigateToParent: (() -> Void)?
    
    init(
        isLoading: Bool,
        errorMessage: String?,
        searchText: String,
        selectedFolderName: String?,
        hasSelectedFolder: Bool,
        parentFolderName: String? = nil,
        onRetry: @escaping () -> Void,
        onNavigateToParent: (() -> Void)? = nil
    ) {
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.searchText = searchText
        self.selectedFolderName = selectedFolderName
        self.hasSelectedFolder = hasSelectedFolder
        self.parentFolderName = parentFolderName
        self.onRetry = onRetry
        self.onNavigateToParent = onNavigateToParent
    }
    
    var body: some View {
        if isLoading {
            ProgressView(.Strings.galleryLoadingFolderContents)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            ContentUnavailableView {
                Label(.Strings.galleryErrorUnableToLoadFolder, systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                if hasSelectedFolder {
                    Button(.Strings.commonRetry) {
                        onRetry()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView {
                Label(
                    String(localized: .Strings.galleryEmptyFolderTitle),
                    systemImage: "photo.on.rectangle.angled"
                )
            } description: {
                Text(.Strings.galleryEmptyFolderDescription(selectedFolderName ?? String(localized: .Strings.galleryEmptyFolderDefaultName)))
            } actions: {
                if let parentFolderName, let onNavigateToParent {
                    Button {
                        onNavigateToParent()
                    } label: {
                        Label(
                            String(localized: .Strings.galleryNavigateParentFolder(parentFolderName)),
                            systemImage: "arrow.up.folder"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
