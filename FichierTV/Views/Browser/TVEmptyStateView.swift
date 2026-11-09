//
//  TVEmptyStateView.swift
//  FichierTV
//

import SwiftUI

/// Empty state display shown when a folder or album contains no items.
public struct TVEmptyStateView: View {
    public let message: String
    public let isShares: Bool
    public let onBack: () -> Void

    public init(
        message: String = "No media found in this folder.",
        isShares: Bool,
        onBack: @escaping () -> Void
    ) {
        self.message = message
        self.isShares = isShares
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "tray")
                .font(.system(.largeTitle))
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(message)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if isShares {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Go back")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusSection()
        .accessibilityElement(children: .contain)
    }
}
