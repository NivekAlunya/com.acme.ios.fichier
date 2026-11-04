//
//  VideoPlaybackStore.swift
//  fichier
//

import Foundation
import Observation

/// Persistent store tracking playback offsets, completion states, and resume positions for video media items.
///
/// ### Architecture & Performance Optimizations
/// - **Actor Isolation**: `@Observable @MainActor public final class`, synchronizing UI badge updates with the main run loop.
/// - **Observation Throttling (`@ObservationIgnored`)**: During active video playback, time observer ticks occur at ~10Hz.
///   Mutating an observed property at that frequency would trigger continuous SwiftUI view re-evaluations across the gallery.
///   Instead, ticks update `@ObservationIgnored private var liveRecords`, and only touch the observed `records` dictionary
///   when the visible UI representation crosses a 5% progress step (`bucket(of:)`).
/// - **Debounced Disk Persistence**: Avoids constant filesystem I/O by debouncing `UserDefaults` saves using a 5-second `Task.sleep` timer.
@Observable
@MainActor
public final class VideoPlaybackStore {
    
    /// Global shared singleton instance.
    public static let shared = VideoPlaybackStore()
    
    /// Observed playback records dictionary powering UI progress bars and status badges in SwiftUI views.
    public private(set) var records: [String: VideoPlaybackRecord] = [:]
    
    /// High-frequency unobserved playback position registry updated on every player tick without invalidating SwiftUI bodies.
    @ObservationIgnored private var liveRecords: [String: VideoPlaybackRecord] = [:]
    
    /// Debounced asynchronous task handle scheduling writes to persistent storage.
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    
    /// Active storage key in `UserDefaults` storing v2 encoded records.
    private let storageKey = "SMBVideoPlaybackRecords_v2"
    
    /// Legacy storage key used for one-time v1 position migration.
    private let legacyKey = "SMBVideoPlaybackPositions_v1"
    
    // MARK: - Initialization & Migration
    
    /// Initializes the store and performs startup data sanitation and legacy v1 migration.
    ///
    /// ### Complex Sanitation Logic:
    /// - Purges spurious records with `< 2.0s` duration or position to avoid false-positive in-progress indicators.
    /// - Flags items as finished if the user watched past 90% or within the final 4 seconds of video runtime.
    /// - Migrates legacy `[String: Double]` entries from v1 format.
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
    
    // MARK: - Status & Position Lookups
    
    /// Evaluates the discrete playback status badge for a media item.
    ///
    /// - Parameter item: The `MediaItem` to evaluate.
    /// - Returns: `.finished`, `.inProgress(progress:)`, or `.unwatched`.
    public func status(for item: MediaItem) -> VideoPlaybackStatus {
        let record = records[item.id] ?? (!item.connectionID.isEmpty ? records["\(item.shareName)::\(item.path)"] : nil)
        guard let record else { return .unwatched }
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
    
    /// Retrieves the saved resume offset for a video if playback was interrupted mid-stream.
    ///
    /// Suppresses resume offsets if the previous playback reached near the end of the video.
    ///
    /// - Parameter item: The video `MediaItem`.
    /// - Returns: The resume timestamp in seconds, or `nil` if the video should start from beginning.
    public func position(for item: MediaItem) -> Double? {
        guard let record = latestRecord(for: item), !record.isFinished, record.position > 3.0 else { return nil }
        // If the saved position is near the end, do not resume at the end
        if record.duration > 0 {
            if record.position >= record.duration - 4.0 || record.position / record.duration >= 0.90 {
                return nil
            }
        }
        return record.position
    }
    
    // MARK: - Playback Updates
    
    /// Records an updated playback progress timestamp from an active video player instance.
    ///
    /// ### Complex Code Breakdown:
    /// - **Sanity Verification**: Discards non-finite or `NaN` numbers and ignores playback under 2 seconds.
    /// - **Auto-Finish Detection**: If position is within the final 4 seconds (or $\ge 90\%$), delegates to `markFinished`.
    /// - **Two-Tier Update**: Updates `liveRecords` synchronously, but only updates observed `records`
    ///   when crossing a visual 5% bucket boundary to conserve rendering cycles.
    /// - **Debounced Disk Save**: Reschedules a 5-second background persistence timer.
    ///
    /// - Parameters:
    ///   - seconds: The current playback head in seconds.
    ///   - duration: The total media duration in seconds.
    ///   - item: The target `MediaItem`.
    public func savePosition(_ seconds: Double, duration: Double, for item: MediaItem) {
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
            
            // Clean up any old legacy key if we're now saving with connectionID
            if !item.connectionID.isEmpty {
                let legacyKey = "\(item.shareName)::\(item.path)"
                records.removeValue(forKey: legacyKey)
                liveRecords.removeValue(forKey: legacyKey)
            }
            
            // Cheap, non-observed update on every tick (no UI invalidation)
            liveRecords[item.id] = updated
            
            // Only touch the observed dictionary when the visible badge / progress bar would change
            if Self.bucket(of: records[item.id]) != Self.bucket(of: updated) {
                records[item.id] = updated
            }
            schedulePersist()
        }
    }
    
    /// Marks a video as completely watched and immediately flushes updates to disk.
    ///
    /// - Parameters:
    ///   - item: The `MediaItem` to complete.
    ///   - duration: Optional explicit duration override.
    public func markFinished(for item: MediaItem, duration: Double = 0) {
        let existing = latestRecord(for: item)
        let dur = duration > 0 ? duration : (existing?.duration ?? 0)
        guard dur >= 2.0 else { return }
        let pos = max(dur, existing?.position ?? 0)
        
        if !item.connectionID.isEmpty {
            let legacyKey = "\(item.shareName)::\(item.path)"
            records.removeValue(forKey: legacyKey)
            liveRecords.removeValue(forKey: legacyKey)
        }
        liveRecords.removeValue(forKey: item.id)
        records[item.id] = VideoPlaybackRecord(position: pos, duration: max(dur, pos), isFinished: true)
        flush()
    }
    
    /// Clears any recorded progress or completion status for a video.
    ///
    /// - Parameter item: The target `MediaItem`.
    public func clearPosition(for item: MediaItem) {
        var changed = false
        if liveRecords.removeValue(forKey: item.id) != nil { changed = true }
        if records.removeValue(forKey: item.id) != nil { changed = true }
        if !item.connectionID.isEmpty {
            let legacyKey = "\(item.shareName)::\(item.path)"
            if liveRecords.removeValue(forKey: legacyKey) != nil { changed = true }
            if records.removeValue(forKey: legacyKey) != nil { changed = true }
        }
        if changed {
            flush()
        }
    }
    
    /// Merges unobserved in-memory positions into the observed dictionary and immediately flushes all records to disk.
    ///
    /// Called when the player view controller is dismissed or during scene backgrounding.
    public func flush() {
        persistTask?.cancel()
        persistTask = nil
        if !liveRecords.isEmpty {
            records.merge(liveRecords) { _, live in live }
            liveRecords.removeAll()
        }
        persist()
    }
    
    // MARK: - Private Helpers
    
    /// Resolves the latest record by checking high-frequency unobserved cache before falling back to observed storage.
    private func latestRecord(for item: MediaItem) -> VideoPlaybackRecord? {
        if let live = liveRecords[item.id] { return live }
        if let rec = records[item.id] { return rec }
        if !item.connectionID.isEmpty {
            let legacyKey = "\(item.shareName)::\(item.path)"
            return liveRecords[legacyKey] ?? records[legacyKey]
        }
        return nil
    }
    
    /// Computes a discrete 5% quantum bucket (`0...20`) representing visible progress ring changes.
    private static func bucket(of record: VideoPlaybackRecord?) -> Int {
        guard let record else { return -1 }
        return record.isFinished ? 100 : Int(record.progress * 20)
    }
    
    /// Schedules a debounced flush task 5 seconds in the future.
    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
    
    /// Serializes records as JSON data to `UserDefaults`.
    private func persist() {
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
