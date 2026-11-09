//
//  MediaPaginationFooterView.swift
//  fichier
//
//

import SwiftUI

/// Footer displaying incremental folder loading progress, retryable pagination errors, or a manual load-more action.
@MainActor
struct MediaPaginationFooterView: View {
    var manager: StorageLocationManager

    var body: some View {
        if manager.isLoadingMore {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 12)
        } else if let errorMessage = manager.paginationErrorMessage {
            VStack(spacing: 8) {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button(.Strings.commonRetry) {
                    Task {
                        await manager.loadNextFolderPage()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if manager.canLoadMorePages {
            HStack {
                Spacer()
                Button {
                    Task {
                        await manager.loadNextFolderPage()
                    }
                } label: {
                    Label(
                        String(localized: "Load More", comment: "Button to load the next page of folder items"),
                        systemImage: "arrow.down.circle"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
            .padding(.vertical, 12)
        }
    }
}
