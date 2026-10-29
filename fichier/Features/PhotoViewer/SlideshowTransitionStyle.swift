//
//  SlideshowTransitionStyle.swift
//  fichier
//

import SwiftUI

public enum SlideshowTransitionStyle: String, CaseIterable, Identifiable {
    case slide = "Slide"
    case dissolve = "Dissolve"
    case kenBurns = "Ken Burns"
    
    public var id: String { rawValue }
    
    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .slide: return .Strings.slideshowTransitionSlide
        case .dissolve: return .Strings.slideshowTransitionDissolve
        case .kenBurns: return .Strings.slideshowTransitionKenBurns
        }
    }
    
    public var iconName: String {
        switch self {
        case .slide: return "arrow.left.and.right.square"
        case .dissolve: return "circle.dotted"
        case .kenBurns: return "camera.macro"
        }
    }
}
