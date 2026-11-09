//
//  TVAddServerCardView.swift
//  FichierTV
//
//

import SwiftUI

/// Visual label for the trailing card allowing users to configure and connect a new SMB server.
public struct TVAddServerCardView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Add Server")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(width: 320, height: 220)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Add Server")
        .accessibilityHint("Discover via Bonjour or configure a new SMB server")
    }
}
