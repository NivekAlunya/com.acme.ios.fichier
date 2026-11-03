//
//  VideoPlaybackState.swift
//  fichier
//

import Foundation

public enum VideoPlaybackState: Equatable, Sendable {
    case idle
    case loading(MediaItem)
    case buffering
    case playing
    case paused
    case failed(String)
    
    public var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
    
    public var isBuffering: Bool {
        switch self {
        case .loading, .buffering: return true
        default: return false
        }
    }
}
