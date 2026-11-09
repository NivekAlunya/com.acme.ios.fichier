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
    
    /// The associated AVFoundation media option, or `nil` representing "Subtitles Off" or extended VLC track.
    public let mediaOption: AVMediaSelectionOption?
    
    /// The associated VLCKit track identifier index, if applicable.
    public let vlcTrackIndex: Int32?
    
    /// Memberwise designated initializer.
    ///
    /// - Parameters:
    ///   - id: Unique option string identifier.
    ///   - displayName: User-facing title.
    ///   - mediaOption: AVFoundation media selection option.
    ///   - vlcTrackIndex: Optional VLCKit track integer index.
    public init(
        id: String,
        displayName: String,
        mediaOption: AVMediaSelectionOption? = nil,
        vlcTrackIndex: Int32? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.mediaOption = mediaOption
        self.vlcTrackIndex = vlcTrackIndex
    }
}
