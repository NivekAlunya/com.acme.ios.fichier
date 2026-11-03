//
//  PDFKitRepresentedView.swift
//  fichier
//

import SwiftUI
import PDFKit

struct PDFKitRepresentedView: UIViewRepresentable {
    let document: PDFDocument
    let onPageChange: ((Int, Int) -> Void)?
    let onTap: (() -> Void)?
    let onPDFViewCreated: ((PDFView) -> Void)?
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemBackground
        pdfView.usePageViewController(false)
        
        context.coordinator.attach(to: pdfView)
        onPDFViewCreated?(pdfView)
        
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document != document {
            uiView.document = document
            context.coordinator.updatePageInfo()
        }
        context.coordinator.onPageChange = onPageChange
        context.coordinator.onTap = onTap
    }
    
    func makeCoordinator() -> PDFKitCoordinator {
        PDFKitCoordinator(onPageChange: onPageChange, onTap: onTap)
    }
    
    static func dismantleUIView(_ uiView: PDFView, coordinator: PDFKitCoordinator) {
        coordinator.detach()
    }
}
