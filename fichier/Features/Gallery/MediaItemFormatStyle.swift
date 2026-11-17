//
//  MediaItemFormatStyle.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Visual styling, format labels, and accent colors for media items displayed on gallery cells.
public enum MediaItemFormatStyle: Sendable {
    
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
        if item.isPDF {
            return "PDF"
        }
        if item.isGIF {
            return "GIF"
        }
        let ext = (item.name as NSString).pathExtension
        if item.isVideo {
            return VideoFormatStyle.label(for: ext)
        }
        let trimmed = ext.trimmingCharacters(in: .punctuationCharacters).uppercased()
        return trimmed.isEmpty ? "PHOTO" : trimmed
    }
    
    /// Returns a distinctive format color for the media item.
    ///
    /// - Parameter item: The target media item.
    /// - Returns: A dedicated `Color` for the item's format family.
    public static func color(for item: MediaItem) -> Color {
        if item.isPDF {
            return Color(red: 0.90, green: 0.25, blue: 0.25) // PDF Coral Red
        }
        if item.isGIF {
            return Color.orange
        }
        let ext = (item.name as NSString).pathExtension.lowercased()
        if item.isVideo {
            return VideoFormatStyle.color(for: ext)
        }
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
