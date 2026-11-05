//
//  VideoFormatStyle.swift
//  fichier
//

import SwiftUI

/// Visual styling and color definitions for video container formats displayed on gallery cells.
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
        switch ext.lowercased() {
        case "mp4":
            return Color.blue
        case "mov":
            return Color.cyan
        case "m4v":
            return Color.indigo
        case "mkv":
            return Color(red: 0.58, green: 0.28, blue: 0.88) // Vivid Purple
        case "avi":
            return Color.orange
        case "webm":
            return Color(red: 0.16, green: 0.68, blue: 0.38) // Emerald Green
        case "flv", "f4v":
            return Color(red: 0.90, green: 0.25, blue: 0.25) // Coral Red
        case "wmv", "asf":
            return Color(red: 0.94, green: 0.62, blue: 0.12) // Warm Amber
        case "ts", "m2ts", "mts":
            return Color.mint
        case "ogv":
            return Color(red: 0.20, green: 0.70, blue: 0.50) // Sea Green
        case "3gp":
            return Color.teal
        default:
            return Color(white: 0.30)
        }
    }
}
