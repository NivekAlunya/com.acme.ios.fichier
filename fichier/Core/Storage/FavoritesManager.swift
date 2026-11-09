//
//  FavoritesManager.swift
//  fichier
//

import UIKit
import Observation

/// Centralized state manager tracking user-favorited media items across local, iCloud, and remote SMB storage.
///
/// ### Architecture & Concurrency
/// - **Actor Isolation**: `@Observable @MainActor public final class`, synchronizing UI favorite states with views directly.
/// - **Persistence**: Stores identifiers as a serialized JSON `Set<String>` in `UserDefaults` for instant startup access.
/// - **Haptics**: Generates dynamic feedback on toggle actions.
@Observable
@MainActor
public final class FavoritesManager {
    
    /// Global shared singleton instance.
    public static let shared = FavoritesManager()
    
    /// The live set of favorited `MediaItem.id` strings.
    public private(set) var favoriteIDs: Set<String> = []
    
    /// Key used for serializing favorites to `UserDefaults`.
    private let key = "SMBUserFavoriteItemIDs_v1"
    
    /// Private initializer restoring previously persisted favorites from `UserDefaults`.
    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.favoriteIDs = decoded
        }
    }
    
    /// Checks whether the specified media item is currently marked as a favorite.
    ///
    /// - Parameter item: The `MediaItem` to test.
    /// - Returns: `true` if favorited; `false` otherwise.
    public func isFavorite(_ item: MediaItem) -> Bool {
        favoriteIDs.contains(item.id)
    }
    
    /// Toggles the favorite status for a given media item and immediately persists the update.
    ///
    /// - Parameter item: The target `MediaItem`.
    public func toggleFavorite(_ item: MediaItem) {
        if favoriteIDs.contains(item.id) {
            favoriteIDs.remove(item.id)
            AppHapticFeedback.light()
        } else {
            favoriteIDs.insert(item.id)
            AppHapticFeedback.medium()
        }
        save()
    }
    
    /// Persists the updated favorite identifiers set into `UserDefaults`.
    private func save() {
        if let encoded = try? JSONEncoder().encode(favoriteIDs) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}
