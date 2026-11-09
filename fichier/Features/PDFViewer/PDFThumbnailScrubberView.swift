//
//  PDFThumbnailScrubberView.swift
//  fichier
//

#if !os(tvOS)
import SwiftUI
import PDFKit

/// SwiftUI wrapper around PDFKit's native `PDFThumbnailView` providing a horizontal scrubber bar.
///
/// Binds directly to an active `PDFView` instance to provide synchronized page scrubbing and thumbnail navigation.
struct PDFThumbnailScrubberView: UIViewRepresentable {
    /// Weak reference to the target `PDFView` being scrubbed.
    weak var pdfView: PDFView?
    
    /// Bounding size of each page thumbnail rendered in the strip.
    var thumbnailSize: CGSize = CGSize(width: 44, height: 60)
    
    func makeUIView(context: Context) -> PDFThumbnailView {
        let thumbnailView = PDFThumbnailView()
        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = thumbnailSize
        thumbnailView.layoutMode = .horizontal
        thumbnailView.backgroundColor = .clear
        return thumbnailView
    }
    
    func updateUIView(_ uiView: PDFThumbnailView, context: Context) {
        if uiView.pdfView !== pdfView {
            uiView.pdfView = pdfView
        }
    }
}

#endif // !os(tvOS)
