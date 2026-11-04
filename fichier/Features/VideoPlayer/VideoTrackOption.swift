//
//  VideoTrackOption.swift
//  fichier
//

import AVFoundation

/// Value model representing an individual selectable audio track or closed caption / subtitle stream.
///
/// Wraps an underlying `AVMediaSelectionOption` (or `nil` for disabling subtitles) with a stable
/// string identifier and localized display title.
public struct VideoTrackOption: Identifiable, Equatable {
    /// Unique identifier for this track option (e.g. `audio_0_English` or `sub_off`).
    public let id: String
    
    /// User-facing display title for this track in menus.
    public let displayName: String
    
    /// The associated AVFoundation media option, or `nil` representing "Subtitles Off".
    public let mediaOption: AVMediaSelectionOption?
    
    /// Memberwise designated initializer.
    ///
    /// - Parameters:
    ///   - id: Unique option string identifier.
    ///   - displayName: User-facing title.
    ///   - mediaOption: AVFoundation media selection option.
    public init(id: String, displayName: String, mediaOption: AVMediaSelectionOption?) {
        self.id = id
        self.displayName = displayName
        self.mediaOption = mediaOption
    }
}
