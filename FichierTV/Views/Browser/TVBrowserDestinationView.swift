//
//  TVBrowserDestinationView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Destination wrapper resolving a `MediaSource` dynamically before presenting `TVMediaBrowserView`.
public struct TVBrowserDestinationView: View {
    public let sourceID: String
    public let folder: MediaSourceItem?

    @State private var resolvedSource: (any MediaSource)?
    @State private var hasAttemptedResolution = false

    public init(sourceID: String, folder: MediaSourceItem?) {
        self.sourceID = sourceID
        self.folder = folder
    }

    public var body: some View {
        Group {
            if let resolvedSource {
                TVMediaBrowserView(source: resolvedSource, folder: folder)
            } else if hasAttemptedResolution {
                TVErrorStateView(
                    message: "Unable to locate media source with identifier: \(sourceID)",
                    onRetry: {
                        Task { await resolve() }
                    }
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await resolve()
        }
    }

    private func resolve() async {
        resolvedSource = await DefaultMediaSourceResolver.shared.resolve(sourceID: sourceID)
        hasAttemptedResolution = true
    }
}
