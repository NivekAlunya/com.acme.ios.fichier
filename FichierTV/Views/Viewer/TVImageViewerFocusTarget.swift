//
//  TVImageViewerFocusTarget.swift
//  FichierTV
//
//

import Foundation

/// Focus targets inside the tvOS image viewer HUD overlay.
public enum TVImageViewerFocusTarget: Hashable, Sendable {
    case close
    case settings
    case previous
    case toggleSlideshow
    case next
}
