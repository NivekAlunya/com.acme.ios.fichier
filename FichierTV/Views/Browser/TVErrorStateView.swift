//
//  TVErrorStateView.swift
//  FichierTV
//

import SwiftUI

/// Error state display presenting failure details alongside a Retry button and optional Back button.
public struct TVErrorStateView: View {
    public let message: String
    public let onBack: (() -> Void)?
    public let onRetry: () -> Void

    public init(
        message: String,
        onBack: (() -> Void)? = nil,
        onRetry: @escaping () -> Void
    ) {
        self.message = message
        self.onBack = onBack
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(.largeTitle))
                .imageScale(.large)
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 80)

            HStack(spacing: 24) {
                if let onBack {
                    Button(action: onBack) {
                        Label(.Strings.commonBack, systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text(.Strings.commonGoBack))
                }

                Button(action: onRetry) {
                    Label(.Strings.commonRetry, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(Text(.Strings.commonRetry))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusSection()
        .accessibilityElement(children: .contain)
    }
}
