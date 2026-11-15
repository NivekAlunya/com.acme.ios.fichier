//
//  FavoritesManager+MediaItem.swift
//  fichier
//

import UIKit
import FichierKit

extension FavoritesManager {
    /// Checks whether the specified media item is currently marked as a favorite.
    ///
    /// - Parameter item: The `MediaItem` to test.
    /// - Returns: `true` if favorited; `false` otherwise.
    public func isFavorite(_ item: MediaItem) -> Bool {
        isFavorite(id: item.id)
    }

    /// Toggles the favorite status for a given media item, triggering haptic feedback, and immediately persists the update.
    ///
    /// - Parameter item: The target `MediaItem`.
    public func toggleFavorite(_ item: MediaItem) {
        let isNowFavorite = toggleFavorite(id: item.id)
        if isNowFavorite {
            AppHapticFeedback.medium()
        } else {
            AppHapticFeedback.light()
        }
    }
}
