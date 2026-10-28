//
//  FavoritesManager.swift
//  fichier
//

import UIKit
import Observation

@Observable
@MainActor
public final class FavoritesManager {
    public static let shared = FavoritesManager()
    
    public private(set) var favoriteIDs: Set<String> = []
    private let key = "SMBUserFavoriteItemIDs_v1"
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.favoriteIDs = decoded
        }
    }
    
    public func isFavorite(_ item: SMBItem) -> Bool {
        favoriteIDs.contains(item.id)
    }
    
    public func toggleFavorite(_ item: SMBItem) {
        if favoriteIDs.contains(item.id) {
            favoriteIDs.remove(item.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            favoriteIDs.insert(item.id)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        save()
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(favoriteIDs) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}
