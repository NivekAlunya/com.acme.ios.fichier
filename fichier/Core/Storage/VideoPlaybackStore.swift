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
    
    public private(set) var records: [String: VideoPlaybackRecord] = [:]
    private let storageKey = "SMBVideoPlaybackRecords_v2"
    private let legacyKey = "SMBVideoPlaybackPositions_v1"
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: VideoPlaybackRecord].self, from: data) {
            self.records = decoded
        } else if let legacyData = UserDefaults.standard.data(forKey: legacyKey),
                  let legacyPositions = try? JSONDecoder().decode([String: Double].self, from: legacyData) {
            // Migrate v1 saved positions
            var migrated: [String: VideoPlaybackRecord] = [:]
            for (id, pos) in legacyPositions where pos >= 3.0 {
                migrated[id] = VideoPlaybackRecord(position: pos, duration: 0, isFinished: false)
            }
            self.records = migrated
            persist()
        }
    }
    
    public func status(for item: SMBItem) -> VideoPlaybackStatus {
        guard let record = records[item.id] else { return .unwatched }
        if record.isFinished {
            return .finished
        }
        if record.position >= 3.0 {
            return .inProgress(progress: record.progress)
        }
        return .unwatched
    }
    
    public func position(for item: SMBItem) -> Double? {
        guard let record = records[item.id], !record.isFinished, record.position > 3.0 else { return nil }
        return record.position
    }
    
    public func isFinished(for item: SMBItem) -> Bool {
        return records[item.id]?.isFinished ?? false
    }
    
    public func savePosition(_ seconds: Double, duration: Double, for item: SMBItem) {
        guard seconds.isFinite && !seconds.isNaN && duration.isFinite && !duration.isNaN else { return }
        
        // If within the last 5 seconds or >= 95% watched, mark completed
        if duration > 0 && (seconds >= duration - 5.0 || seconds / duration >= 0.95) {
            markFinished(for: item, duration: duration)
        } else if seconds >= 3.0 {
            records[item.id] = VideoPlaybackRecord(position: seconds, duration: duration, isFinished: false)
            persist()
        }
    }
    
    public func markFinished(for item: SMBItem, duration: Double = 0) {
        let dur = duration > 0 ? duration : (records[item.id]?.duration ?? 0)
        records[item.id] = VideoPlaybackRecord(position: dur, duration: dur, isFinished: true)
        persist()
    }
    
    public func clearPosition(for item: SMBItem) {
        if records.removeValue(forKey: item.id) != nil {
            persist()
        }
    }
    
    private func persist() {
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
