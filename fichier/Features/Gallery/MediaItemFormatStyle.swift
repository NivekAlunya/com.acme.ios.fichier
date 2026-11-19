//
//  MediaItemFormatStyle.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Visual styling, format labels, and accent colors for media items displayed on gallery cells.
///
/// Delegates formatting and color resolution to `FichierKit.MediaFormatStyle`.
public enum MediaItemFormatStyle: Sendable {
    
    /// Resolves format badge label, accent color, and SF Symbol pictogram in a single pass.
    ///
    /// - Parameter item: The target media item.
    /// - Returns: A tuple containing the format label, color, and pictogram SF Symbol name.
    public static func formatInfo(for item: MediaItem) -> (label: String, color: Color, pictogramName: String) {
        let type: MediaItemType = item.isVideo ? .video : .image
        return MediaFormatStyle.formatInfo(
            name: item.name,
            type: type,
            isPDF: item.isPDF,
            isGIF: item.isGIF
        )
    }

    /// Returns the SF Symbol name describing the item's media format type.
    ///
    /// - Parameter item: The target media item.
    /// - Returns: An SF Symbol name (`"play.fill"` for video, `"photo.fill"` for photos, `"doc.text.fill"` for PDF).
    public static func pictogramName(for item: MediaItem) -> String {
        formatInfo(for: item).pictogramName
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
}
