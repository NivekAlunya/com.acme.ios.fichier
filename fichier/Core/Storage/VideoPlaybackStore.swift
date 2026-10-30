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
    
    /// Latest in-progress positions, updated on every player tick.
    /// Not observed, so frequent updates never re-render the gallery.
    @ObservationIgnored private var liveRecords: [String: VideoPlaybackRecord] = [:]
    @ObservationIgnored private var persistTask: Task<Void, Never>?
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
        guard let record = latestRecord(for: item), !record.isFinished, record.position > 3.0 else { return nil }
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
            let updated = VideoPlaybackRecord(position: seconds, duration: duration, isFinished: false)
            
            // Cheap, non-observed update on every tick (no UI invalidation)
            liveRecords[item.id] = updated
            
            // Only touch the observed dictionary when the visible badge / progress bar would change
            if Self.bucket(of: records[item.id]) != Self.bucket(of: updated) {
                records[item.id] = updated
            }
            schedulePersist()
        }
    }
    
    public func markFinished(for item: SMBItem, duration: Double = 0) {
        let existing = latestRecord(for: item)
        let dur = duration > 0 ? duration : (existing?.duration ?? 0)
        guard dur >= 2.0 else { return }
        let pos = max(dur, existing?.position ?? 0)
        liveRecords.removeValue(forKey: item.id)
        records[item.id] = VideoPlaybackRecord(position: pos, duration: max(dur, pos), isFinished: true)
        flush()
    }
    
    public func clearPosition(for item: SMBItem) {
        let hadLive = liveRecords.removeValue(forKey: item.id) != nil
        let hadRecord = records.removeValue(forKey: item.id) != nil
        if hadLive || hadRecord {
            flush()
        }
    }
    
    /// Merges the live (non-observed) positions into the observed records and writes everything to disk.
    /// Call when the player is torn down or the app goes to the background.
    public func flush() {
        persistTask?.cancel()
        persistTask = nil
        if !liveRecords.isEmpty {
            records.merge(liveRecords) { _, live in live }
            liveRecords.removeAll()
        }
        persist()
    }
    
    // MARK: - Private
    
    private func latestRecord(for item: SMBItem) -> VideoPlaybackRecord? {
        liveRecords[item.id] ?? records[item.id]
    }
    
    /// Coarse visual state of a record: changes only when the badge or the progress bar would change (5% steps).
    private static func bucket(of record: VideoPlaybackRecord?) -> Int {
        guard let record else { return -1 }
        return record.isFinished ? 100 : Int(record.progress * 20)
    }
    
    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
    
    private func persist() {
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
