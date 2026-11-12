//
//  TVVideoOverlayFocusTarget.swift
//  FichierTV
//
//

import Foundation

/// Focus targets inside the two-row tvOS video player HUD overlay.
public enum TVVideoOverlayFocusTarget: Hashable, Sendable {
    case progress
    case previous
    case playPause
    case next
    case switchEngine
    case chapters
    case tracks
    case speed
}
