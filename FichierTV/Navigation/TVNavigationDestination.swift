//
//  TVNavigationDestination.swift
//  FichierTV
//

import Foundation
import FichierKit

/// Navigation destinations pushed onto the tvOS `NavigationStack`.
public enum TVNavigationDestination: Hashable, Sendable {
    /// Drills down into a folder or album within a specific media source.
    case browser(sourceID: String, folder: MediaSourceItem?)

    /// Pushes the image viewer with the selected item and its sibling collection context.
    case imageViewer(
        item: MediaSourceItem,
        context: [MediaSourceItem],
        pagination: TVViewerPaginationContext? = nil
    )

    /// Pushes the video player with the selected item and its playlist context.
    case videoPlayer(item: MediaSourceItem, context: [MediaSourceItem])

    /// Presents the full-screen form to add a new SMB server.
    case addServer

    /// Presents the full-screen form to edit an existing SMB server.
    case editServer(SavedSMBConnection)
}
