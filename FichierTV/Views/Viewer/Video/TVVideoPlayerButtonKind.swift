//
//  TVVideoPlayerButtonKind.swift
//  FichierTV
//

import Foundation

/// Button identifiers within the buttons row of the video player overlay.
public enum TVVideoPlayerButtonKind: Hashable, Sendable {
    case previous
    case playPause
    case next
    case switchEngine
    case chapters
    case tracks
    case speed
}
