//
//  MediaItemFormatStyle.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Visual styling, format labels, and accent colors for media items displayed on gallery cells.
public enum MediaItemFormatStyle: Sendable {
    
    /// Resolves format badge label, accent color, and SF Symbol pictogram in a single pass.
    ///
    /// - Parameter item: The target media item.
    /// - Returns: A tuple containing the format label, color, and pictogram SF Symbol name.
    public static func formatInfo(for item: MediaItem) -> (label: String, color: Color, pictogramName: String) {
        if item.isPDF {
            return ("PDF", Color(red: 0.90, green: 0.25, blue: 0.25), "doc.text.fill")
        }
        if item.isGIF {
            return ("GIF", Color.orange, "photo.fill")
        }
        
        let ext = (item.name as NSString).pathExtension
        if item.isVideo {
            let label = VideoFormatStyle.label(for: ext)
            let color = VideoFormatStyle.color(for: ext.lowercased())
            return (label, color, "play.fill")
        }
        
        let trimmed = ext.trimmingCharacters(in: .punctuationCharacters)
        let label = trimmed.isEmpty ? "PHOTO" : trimmed.uppercased()
        let color = photoColor(forExtension: trimmed.lowercased())
        return (label, color, "photo.fill")
    }

    /// Returns the SF Symbol name describing the item's media format type.
    ///
    /// - Parameter item: The target media item.
    /// - Returns: An SF Symbol name (`"play.fill"` for video, `"photo.fill"` for photos, `"doc.text.fill"` for PDF).
    public static func pictogramName(for item: MediaItem) -> String {
        if item.isVideo {
            return "play.fill"
        }
        if item.isPDF {
            return "doc.text.fill"
        }
        return "photo.fill"
    }

    /// Formats the item's type/extension into an uppercase badge string (e.g. "MP4", "PNG", "PDF").
    ///
    /// - Parameter item: The target media item.
    /// - Returns: A normalized uppercase badge label.
    public static func label(for item: MediaItem) -> String {
        formatInfo(for: item).label
    }
    
    /// Returns a distinctive format color for the media item.
    ///
    /// - Parameter item: The target media item.
    /// - Returns: A dedicated `Color` for the item's format family.
    public static func color(for item: MediaItem) -> Color {
        formatInfo(for: item).color
    }

    private static func photoColor(forExtension ext: String) -> Color {
        switch ext {
        case "png":
            return Color.teal
        case "jpg", "jpeg", "jpe", "jfif":
            return Color.green
        case "heic", "heif":
            return Color.cyan
        case "webp", "avif":
            return Color.blue
        case "dng", "cr2", "cr3", "nef", "arw", "raw", "orf", "rw2":
            return Color(red: 0.58, green: 0.28, blue: 0.88) // Vivid Purple / RAW
        case "tif", "tiff":
            return Color.indigo
        default:
            return Color(white: 0.30)
        }
    }
}
