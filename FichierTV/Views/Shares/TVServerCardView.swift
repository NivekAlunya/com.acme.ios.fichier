//
//  TVServerCardView.swift
//  FichierTV
//
//

import SwiftUI
import FichierKit

/// Visual card content presenting an SMB server's name, host, and live reachability badge.
public struct TVServerCardView: View {
    public let card: ServerCardItem

    public init(card: ServerCardItem) {
        self.card = card
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: "server.rack")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Spacer()

                statusBadge
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text(card.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(card.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(24)
        .frame(width: 320, height: 220)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(.Strings.tvServerCardAccessibility(card.name, card.host, String(localized: statusTitle))))
        .accessibilityHint(Text(.Strings.tvServerCardAccessibilityHint))
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var statusTitle: LocalizedStringResource {
        switch card.status {
        case .online:
            return .Strings.tvServerStatusOnline
        case .offline:
            return .Strings.tvServerStatusOffline
        case .connecting:
            return .Strings.tvServerStatusConnecting
        case .unknown:
            return .Strings.tvServerStatusUnknown
        }
    }

    private var statusColor: Color {
        switch card.status {
        case .online:
            return FichierTheme.connected
        case .offline:
            return .red
        case .connecting:
            return FichierTheme.attention
        case .unknown:
            return .gray
        }
    }
}
