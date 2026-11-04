//
//  MediaActivityShareSheet.swift
//  fichier
//

import SwiftUI
import UIKit

/// SwiftUI bridge wrapping UIKit's `UIActivityViewController` for sharing media files and URLs.
///
/// Encapsulates native system sharing, AirDrop, Messages, Mail, and third-party extension targets.
struct MediaActivityShareSheet: UIViewControllerRepresentable {
    /// Array of objects to share (typically file URLs, images, or strings).
    let activityItems: [Any]
    
    /// Instantiates the underlying `UIActivityViewController`.
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    /// Conformance placeholder; dynamic updates are handled by dismissing and re-presenting the sheet.
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
