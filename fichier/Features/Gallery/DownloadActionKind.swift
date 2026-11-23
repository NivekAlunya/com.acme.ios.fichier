//
//  DownloadActionKind.swift
//  fichier
//

import Foundation

/// Distinguishes the destination for a user-initiated media download action.
enum DownloadActionKind: Equatable, Sendable {
    case saveToPhotos
    case downloadToFiles
}
