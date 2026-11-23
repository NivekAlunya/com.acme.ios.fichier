//
//  PendingDownloadConfirmation.swift
//  fichier
//

import Foundation

/// Represents a pending download or Photos export awaiting user confirmation.
struct PendingDownloadConfirmation: Equatable, Sendable {
    let items: [MediaItem]
    let kind: DownloadActionKind
}
