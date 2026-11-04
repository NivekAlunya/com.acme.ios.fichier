//
//  SlideDirection.swift
//  fichier
//

import Foundation

/// Navigation trajectory direction for transitions between consecutive images in slideshow mode.
enum SlideDirection {
    /// Moving forward to the subsequent photo (animates from right/trailing to left/leading).
    case forward
    
    /// Moving backward to the preceding photo (animates from left/leading to right/trailing).
    case backward
}
