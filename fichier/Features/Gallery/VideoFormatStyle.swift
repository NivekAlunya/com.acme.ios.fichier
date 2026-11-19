//
//  VideoFormatStyle.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Visual styling and color definitions for video container formats displayed on gallery cells.
///
/// Delegates color resolution to `FichierKit.MediaFormatStyle`.
public enum VideoFormatStyle: Sendable {
    
    /// Formats the file extension into a clean uppercase display label.
    ///
    /// - Parameter ext: The raw file extension string.
    /// - Returns: An uppercase representation (e.g. "MKV", "MP4", "AVI") or "VIDEO" if empty.
    public static func label(for ext: String) -> String {
        let trimmed = ext.trimmingCharacters(in: .punctuationCharacters).uppercased()
        return trimmed.isEmpty ? "VIDEO" : trimmed
    }
    
    /// Returns a distinctive SwiftUI accent color for the specified video format.
    ///
    /// - Parameter ext: The video file extension.
    /// - Returns: A dedicated `Color` for the format family.
    public static func color(for ext: String) -> Color {
        MediaFormatStyle.videoColor(forExtension: ext)
    }
}
