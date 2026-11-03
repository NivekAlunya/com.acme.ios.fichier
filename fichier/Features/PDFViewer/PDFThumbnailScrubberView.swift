//
//  PDFThumbnailScrubberView.swift
//  fichier
//

import SwiftUI
import PDFKit

struct PDFThumbnailScrubberView: UIViewRepresentable {
    weak var pdfView: PDFView?
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
