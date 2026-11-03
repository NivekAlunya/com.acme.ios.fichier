//
//  PDFKitRepresentedView.swift
//  fichier
//

import SwiftUI
import PDFKit

struct PDFKitRepresentedView: UIViewRepresentable {
    let document: PDFDocument
    var isBookMode: Bool = false
    var displaysAsBook: Bool = true
    let onPageChange: ((Int, Int) -> Void)?
    var onPageRangeChange: ((Int, Int, Int) -> Void)? = nil
    let onTap: (() -> Void)?
    var onCoordinatorCreated: ((PDFKitCoordinator) -> Void)? = nil
    let onPDFViewCreated: ((PDFView) -> Void)?
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = isBookMode ? .twoUp : .singlePageContinuous
        pdfView.displaysAsBook = displaysAsBook
        pdfView.displayDirection = isBookMode ? .horizontal : .vertical
        pdfView.backgroundColor = .systemBackground
        
        context.coordinator.attach(to: pdfView)
        Task { @MainActor in
            onPDFViewCreated?(pdfView)
        }
        
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document != document {
            uiView.document = document
            Task { @MainActor [weak coordinator = context.coordinator] in
                coordinator?.updatePageInfo()
            }
        }
        
        let targetDisplayMode: PDFDisplayMode = isBookMode ? .twoUp : .singlePageContinuous
        let targetDirection: PDFDisplayDirection = isBookMode ? .horizontal : .vertical
        
        var modeChanged = false
        if uiView.displayMode != targetDisplayMode {
            uiView.displayMode = targetDisplayMode
            modeChanged = true
        }
        if uiView.displaysAsBook != displaysAsBook {
            uiView.displaysAsBook = displaysAsBook
            modeChanged = true
        }
        if uiView.displayDirection != targetDirection {
            uiView.displayDirection = targetDirection
            modeChanged = true
        }
        
        if modeChanged {
            uiView.autoScales = true
            Task { @MainActor [weak coordinator = context.coordinator] in
                coordinator?.updatePageInfo()
            }
        }
        
        context.coordinator.isBookMode = isBookMode
        context.coordinator.updateScrollState()
        context.coordinator.onPageChange = onPageChange
        context.coordinator.onPageRangeChange = onPageRangeChange
        context.coordinator.onTap = onTap
    }
    
    func makeCoordinator() -> PDFKitCoordinator {
        let coordinator = PDFKitCoordinator(
            isBookMode: isBookMode,
            onPageChange: onPageChange,
            onPageRangeChange: onPageRangeChange,
            onTap: onTap
        )
        Task { @MainActor in
            onCoordinatorCreated?(coordinator)
        }
        return coordinator
    }
    
    static func dismantleUIView(_ uiView: PDFView, coordinator: PDFKitCoordinator) {
        coordinator.detach()
    }
}
