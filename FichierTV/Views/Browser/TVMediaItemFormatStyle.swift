//
//  TVMediaItemFormatStyle.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Visual styling, format labels, and accent colors for media source items displayed on tvOS gallery cells.
public enum TVMediaItemFormatStyle: Sendable {
    
    /// Resolves format badge label, accent color, and SF Symbol pictogram in a single pass.
    ///
    /// - Parameter item: The target media source item.
    /// - Returns: A tuple containing the format label, color, and pictogram SF Symbol name.
    public static func formatInfo(for item: MediaSourceItem) -> (label: String, color: Color, pictogramName: String) {
        switch item.type {
        case .folder:
            let label = item.size > 0 ? "\(item.size)" : "FOLDER"
            return (label: label, color: Color(white: 0.35), pictogramName: "folder.fill")
        case .video:
            let rawExt = (item.name as NSString).pathExtension.trimmingCharacters(in: .punctuationCharacters)
            let lowerExt = rawExt.lowercased()
            let label = rawExt.isEmpty ? "VIDEO" : rawExt.uppercased()
            let color = videoColor(forExtension: lowerExt)
            return (label: label, color: color, pictogramName: "play.fill")
        case .image:
            let rawExt = (item.name as NSString).pathExtension.trimmingCharacters(in: .punctuationCharacters)
            let lowerExt = rawExt.lowercased()
            let label = rawExt.isEmpty ? "PHOTO" : rawExt.uppercased()
            let color = imageColor(forExtension: lowerExt)
            return (label: label, color: color, pictogramName: "photo.fill")
        }
    }
    
    /// Returns the SF Symbol name describing the item's media format type.
    ///
    /// - Parameter item: The target media source item.
    /// - Returns: An SF Symbol name (`"play.fill"` for video, `"photo.fill"` for image, `"folder.fill"` for folder).
    public static func pictogramName(for item: MediaSourceItem) -> String {
        formatInfo(for: item).pictogramName
    }
    
    /// Formats the item's type or file extension into an uppercase badge string (e.g. "MP4", "PNG", folder item count).
    ///
    /// - Parameter item: The target media source item.
    /// - Returns: A normalized uppercase badge label.
    public static func label(for item: MediaSourceItem) -> String {
        formatInfo(for: item).label
    }
    
    /// Returns a distinctive format accent color matching the iOS gallery design system.
    ///
    /// - Parameter item: The target media source item.
    /// - Returns: A dedicated `Color` for the format family.
    public static func color(for item: MediaSourceItem) -> Color {
        formatInfo(for: item).color
    }

    private static func videoColor(forExtension ext: String) -> Color {
        switch ext {
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

    private static func imageColor(forExtension ext: String) -> Color {
        switch ext {
        case "png":
            return Color.teal
        case "jpg", "jpeg", "jpe", "jfif":
            return Color.green
        case "heic", "heif":
            return Color.cyan
        case "webp", "avif":
            return Color.blue
        case "gif":
            return Color.orange
        case "dng", "cr2", "cr3", "nef", "arw", "raw", "orf", "rw2":
            return Color(red: 0.58, green: 0.28, blue: 0.88) // Vivid Purple / RAW
        case "tif", "tiff":
            return Color.indigo
        case "pdf":
            return Color(red: 0.90, green: 0.25, blue: 0.25) // PDF Coral Red
        default:
            return Color(white: 0.30)
        }
    }
}
