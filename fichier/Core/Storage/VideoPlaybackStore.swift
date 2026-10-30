//
//  VideoPlaybackStore.swift
//  fichier
//

import Foundation
import Observation

@Observable
@MainActor
public final class VideoPlaybackStore {
    public static let shared = VideoPlaybackStore()
    
    public private(set) var savedPositions: [String: Double] = [:]
    private let storageKey = "SMBVideoPlaybackPositions_v1"
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.savedPositions = decoded
        }
    }
    
    public func position(for item: SMBItem) -> Double? {
        guard let pos = savedPositions[item.id], pos > 3.0 else { return nil }
        return pos
    }
    
    public func savePosition(_ seconds: Double, duration: Double, for item: SMBItem) {
        guard seconds.isFinite && !seconds.isNaN && duration.isFinite && !duration.isNaN else { return }
        
        // If within the last 5 seconds or >= 95% watched, consider completed and clear
        if duration > 0 && (seconds >= duration - 5.0 || seconds / duration >= 0.95) {
            clearPosition(for: item)
        } else if seconds >= 3.0 {
            savedPositions[item.id] = seconds
            persist()
        }
    }
    
    public func clearPosition(for item: SMBItem) {
        if savedPositions.removeValue(forKey: item.id) != nil {
            persist()
        }
    }
    
    private func persist() {
        if let encoded = try? JSONEncoder().encode(savedPositions) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
