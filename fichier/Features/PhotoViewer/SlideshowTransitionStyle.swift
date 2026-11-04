//
//  SlideshowTransitionStyle.swift
//  fichier
//

import SwiftUI

/// Visual transition styles available during automated photo slideshow presentation.
public enum SlideshowTransitionStyle: String, CaseIterable, Identifiable {
    /// Horizontal sliding motion combined with subtle cross-fading.
    case slide = "Slide"
    
    /// Smooth continuous alpha cross-dissolve between successive images.
    case dissolve = "Dissolve"
    
    /// Subtle pan-and-scale Ken Burns documentary animation style.
    case kenBurns = "Ken Burns"
    
    /// Stable string identifier for `Identifiable` conformance.
    public var id: String { rawValue }
    
    /// Localized string resource representing the transition name in menus.
    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .slide: return .Strings.slideshowTransitionSlide
        case .dissolve: return .Strings.slideshowTransitionDissolve
        case .kenBurns: return .Strings.slideshowTransitionKenBurns
        }
    }
    
    /// SF Symbol icon name representing the transition style.
    public var iconName: String {
        switch self {
        case .slide: return "arrow.left.and.right.square"
        case .dissolve: return "circle.dotted"
        case .kenBurns: return "camera.macro"
        }
    }
}
