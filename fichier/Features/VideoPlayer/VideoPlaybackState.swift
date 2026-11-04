//
//  VideoPlaybackState.swift
//  fichier
//

import Foundation

/// Discrete operational states representing the lifecycle of video playback in `VideoPlayerController`.
public enum VideoPlaybackState: Equatable, Sendable {
    /// No video asset is currently loaded.
    case idle
    
    /// Initializing streams and resolving remote or local file assets for the specified media item.
    case loading(MediaItem)
    
    /// The player is waiting for network buffers to accumulate before rendering subsequent frames.
    case buffering
    
    /// Video is actively rendering frames and advancing playback time.
    case playing
    
    /// Video playback is suspended by user action or scrubbing.
    case paused
    
    /// A fatal streaming or decoding error occurred, carrying a sanitized localized description.
    case failed(String)
    
    /// Indicates whether the player is currently actively playing.
    public var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
    
    /// Indicates whether the player is blocked waiting for asset loading or network buffering.
    public var isBuffering: Bool {
        switch self {
        case .loading, .buffering: return true
        default: return false
        }
    }
}
