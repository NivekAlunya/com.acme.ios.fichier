//
//  VideoTrackOption.swift
//  fichier
//

import AVFoundation
import FichierKit

/// Value model representing an individual selectable audio track or closed caption / subtitle stream.
///
/// Wraps an underlying `AVMediaSelectionOption` or `FichierKit` track model (or `nil` for disabling subtitles)
/// with a stable string identifier and localized display title.
public struct VideoTrackOption: Identifiable, Equatable {
    /// Unique identifier for this track option (e.g. `audio_0_English` or `sub_off`).
    public let id: String
    
    /// User-facing display title for this track in menus.
    public let displayName: String
    
    /// The associated AVFoundation media option, or `nil` representing "Subtitles Off" or extended player track.
    public let mediaOption: AVMediaSelectionOption?
    
    /// The associated `FichierKit` audio track, if applicable.
    public let playerAudioTrack: PlayerAudioTrack?
    
    /// The associated `FichierKit` subtitle track, if applicable.
    public let playerSubtitleTrack: PlayerSubtitleTrack?
    
    /// Memberwise designated initializer.
    ///
    /// - Parameters:
    ///   - id: Unique option string identifier.
    ///   - displayName: User-facing title.
    ///   - mediaOption: AVFoundation media selection option.
    ///   - playerAudioTrack: Optional `FichierKit` audio track descriptor.
    ///   - playerSubtitleTrack: Optional `FichierKit` subtitle track descriptor.
    public init(
        id: String,
        displayName: String,
        mediaOption: AVMediaSelectionOption? = nil,
        playerAudioTrack: PlayerAudioTrack? = nil,
        playerSubtitleTrack: PlayerSubtitleTrack? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.mediaOption = mediaOption
        self.playerAudioTrack = playerAudioTrack
        self.playerSubtitleTrack = playerSubtitleTrack
    }
}
