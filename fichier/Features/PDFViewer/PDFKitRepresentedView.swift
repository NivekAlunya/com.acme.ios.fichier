//
//  PDFKitRepresentedView.swift
//  fichier
//

import SwiftUI
import PDFKit

/// SwiftUI bridge wrapping PDFKit's `PDFView` for high-performance vector document browsing.
///
/// Configures display parameters based on the active reading mode:
/// - In book mode: `displayMode = .twoUp`, `displayDirection = .horizontal`, `displaysAsBook = true`.
/// - In continuous mode: `displayMode = .singlePageContinuous`, `displayDirection = .vertical`.
///
/// Coordinates page change notifications, gesture attachments, and automatic scale fitting (`autoScales = true`).
struct PDFKitRepresentedView: UIViewRepresentable {
    /// PDFKit document instance displayed.
    let document: PDFDocument
    
    /// Indicates whether two-page horizontal layout is active.
    var isBookMode: Bool = false
    
    /// Indicates whether Page 1 is treated as an isolated cover page.
    var displaysAsBook: Bool = true
    
    /// Callback delivering current page and total count.
    let onPageChange: ((Int, Int) -> Void)?
    
    /// Callback delivering visible page range and total count.
    var onPageRangeChange: ((Int, Int, Int) -> Void)?
    
    /// Callback invoked when tapping the canvas.
    let onTap: (() -> Void)?
    
    /// Closure receiving the created coordinator instance.
    var onCoordinatorCreated: ((PDFKitCoordinator) -> Void)?
    
    /// Closure receiving the created `PDFView` instance.
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
