//
//  VideoPlaybackStore+MediaItem.swift
//  fichier
//

import Foundation
import FichierKit

extension VideoPlaybackStore {
    private func fallbackKey(for item: MediaItem) -> String? {
        item.connectionID.isEmpty ? nil : "\(item.shareName)::\(item.path)"
    }

    /// Evaluates the discrete playback status badge for a `MediaItem`.
    ///
    /// - Parameter item: The `MediaItem` to evaluate.
    /// - Returns: `.finished`, `.inProgress(progress:)`, or `.unwatched`.
    public func status(for item: MediaItem) -> VideoPlaybackStatus {
        status(for: item.id, fallbackKey: fallbackKey(for: item))
    }

    /// Retrieves the saved resume offset for a `MediaItem` if interrupted mid-stream.
    ///
    /// - Parameter item: The video `MediaItem`.
    /// - Returns: The resume timestamp in seconds, or `nil` if playback should start from the beginning.
    public func position(for item: MediaItem) -> Double? {
        position(for: item.id, fallbackKey: fallbackKey(for: item))
    }

    /// Records an updated playback progress timestamp from an active video player instance.
    ///
    /// - Parameters:
    ///   - seconds: The current playback head in seconds.
    ///   - duration: The total media duration in seconds.
    ///   - item: The target `MediaItem`.
    public func savePosition(_ seconds: Double, duration: Double, for item: MediaItem) {
        savePosition(seconds, duration: duration, for: item.id, fallbackKey: fallbackKey(for: item))
    }

    /// Marks a video as completely watched and immediately flushes updates to disk.
    ///
    /// - Parameters:
    ///   - item: The `MediaItem` to complete.
    ///   - duration: Optional explicit duration override.
    public func markFinished(for item: MediaItem, duration: Double = 0) {
        markFinished(for: item.id, fallbackKey: fallbackKey(for: item), duration: duration)
    }

    /// Clears any recorded progress or completion status for a video.
    ///
    /// - Parameter item: The target `MediaItem`.
    public func clearPosition(for item: MediaItem) {
        clearPosition(for: item.id, fallbackKey: fallbackKey(for: item))
    }
}
