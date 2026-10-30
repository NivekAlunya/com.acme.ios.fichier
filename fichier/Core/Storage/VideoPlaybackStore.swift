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
            // Clean up any bogus records where duration < 2.0 or position < 2.0
            var valid: [String: VideoPlaybackRecord] = [:]
            for (id, record) in decoded {
                var rec = record
                if rec.duration > 0 && (rec.position >= rec.duration - 4.0 || rec.progress >= 0.90) {
                    rec.isFinished = true
                }
                if rec.isFinished {
                    if rec.duration >= 2.0 || rec.position >= 2.0 {
                        valid[id] = rec
                    }
                } else if rec.position >= 2.0 {
                    valid[id] = rec
                }
            }
            self.records = valid
            persist()
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
        if record.duration > 0 && (record.position >= record.duration - 4.0 || record.progress >= 0.90) {
            return .finished
        }
        if record.position >= 3.0 {
            return .inProgress(progress: record.progress)
        }
        return .unwatched
    }
    
    public func position(for item: SMBItem) -> Double? {
        guard let record = records[item.id], !record.isFinished, record.position > 3.0 else { return nil }
        // If the saved position is near the end, do not resume at the end
        if record.duration > 0 {
            if record.position >= record.duration - 4.0 || record.position / record.duration >= 0.90 {
                return nil
            }
        }
        return record.position
    }
    
    public func isFinished(for item: SMBItem) -> Bool {
        return records[item.id]?.isFinished ?? false
    }
    
    public func savePosition(_ seconds: Double, duration: Double, for item: SMBItem) {
        guard seconds.isFinite && !seconds.isNaN && duration.isFinite && !duration.isNaN else { return }
        
        // A video with less than 2 seconds played must never be considered completed or in-progress
        guard seconds >= 2.0 else { return }
        
        // Only mark finished if watched to completion (>= 90% of duration, or within last 4s for videos > 15s)
        let isNearEnd = duration > 15.0 ? (seconds >= duration - 4.0) : (duration > 0 && seconds >= duration - 1.5)
        let isHighPercentage = duration > 0 ? (seconds / duration >= 0.90) : false
        
        if duration > 0 && (isNearEnd || isHighPercentage) {
            markFinished(for: item, duration: duration)
        } else if seconds >= 3.0 {
            records[item.id] = VideoPlaybackRecord(position: seconds, duration: duration, isFinished: false)
            persist()
        }
    }
    
    public func markFinished(for item: SMBItem, duration: Double = 0) {
        let dur = duration > 0 ? duration : (records[item.id]?.duration ?? 0)
        let pos = max(dur, records[item.id]?.position ?? 0)
        records[item.id] = VideoPlaybackRecord(position: pos, duration: max(dur, pos), isFinished: true)
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
