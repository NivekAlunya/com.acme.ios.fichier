//
//  TVMediaItemFormatStyle.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Visual styling, format labels, and accent colors for media source items displayed on tvOS gallery cells.
///
/// Delegates all formatting logic to `FichierKit.MediaFormatStyle`.
public enum TVMediaItemFormatStyle: Sendable {
    
    /// Resolves format badge label, accent color, and SF Symbol pictogram in a single pass.
    ///
    /// - Parameter item: The target media source item.
    /// - Returns: A tuple containing the format label, color, and pictogram SF Symbol name.
    public static func formatInfo(for item: MediaSourceItem) -> (label: String, color: Color, pictogramName: String) {
        MediaFormatStyle.formatInfo(for: item)
    }
    
    /// Returns the SF Symbol name describing the item's media format type.
    ///
    /// - Parameter item: The target media source item.
    /// - Returns: An SF Symbol name (`"play.fill"` for video, `"photo.fill"` for image, `"folder.fill"` for folder).
    public static func pictogramName(for item: MediaSourceItem) -> String {
        MediaFormatStyle.pictogramName(for: item)
    }
    
    /// Formats the item's type or file extension into an uppercase badge string (e.g. "MP4", "PNG", folder item count).
    ///
    /// - Parameter item: The target media source item.
    /// - Returns: A normalized uppercase badge label.
    public static func label(for item: MediaSourceItem) -> String {
        MediaFormatStyle.label(for: item)
    }
    
    /// Returns a distinctive format accent color matching the iOS gallery design system.
    ///
    /// - Parameter item: The target media source item.
    /// - Returns: A dedicated `Color` for the format family.
    public static func color(for item: MediaSourceItem) -> Color {
        MediaFormatStyle.color(for: item)
    }
}
