//
//  PDFKitCoordinator.swift
//  fichier
//

import UIKit
import PDFKit

/// Coordinator managing `PDFViewDelegate` callbacks, notification observers, and gestures for `PDFView`.
///
/// ### Core Responsibilities
/// - **Page Synchronization**: Listens for `.PDFViewPageChanged` notifications to report active page numbers
///   and visible multi-page ranges to parent SwiftUI views.
/// - **Scroll / Zoom State Management**: In book mode, disables internal scroll view panning when at 1.0x scale
///   so that finger drags turn pages instead of panning. Re-enables scrolling when zoomed in for deep reading.
/// - **Debounced Navigation**: Provides `goToNext()` and `goToPrevious()` methods throttled by a 250ms window
///   with tactile haptic feedback (`UIImpactFeedbackGenerator`).
/// - **Pan Gesture Recognition**: Captures swipe velocity and horizontal translation in book mode to turn pages.
@MainActor
final class PDFKitCoordinator: NSObject, PDFViewDelegate, UIGestureRecognizerDelegate {
    /// Weak reference to the underlying `PDFView` being managed.
    weak var pdfView: PDFView?
    
    /// Indicates whether the view is operating in horizontal book mode rather than vertical continuous scroll.
    var isBookMode: Bool = false
    
    /// Callback delivering the 1-based current page and total page count.
    var onPageChange: ((Int, Int) -> Void)?
    
    /// Callback delivering the 1-based visible range (`firstPage`, `lastPage`, `total`).
    var onPageRangeChange: ((Int, Int, Int) -> Void)?
    
    /// Callback invoked when a single tap is detected on the canvas.
    var onTap: (() -> Void)?
    
    private var pageObservationTask: Task<Void, Never>?
    private var scaleObservationTask: Task<Void, Never>?
    private var panGesture: UIPanGestureRecognizer?
    private var lastPageTurnTime: TimeInterval = 0
    
    /// Recursively discovers the nested `UIScrollView` embedded inside PDFKit's view hierarchy.
    var internalScrollView: UIScrollView? {
        func findScrollView(in view: UIView) -> UIScrollView? {
            for sub in view.subviews {
                if let scroll = sub as? UIScrollView {
                    return scroll
                }
                if let nested = findScrollView(in: sub) {
                    return nested
                }
            }
            return nil
        }
        return pdfView.flatMap { findScrollView(in: $0) }
    }
    
    /// Memberwise initializer.
    init(
        isBookMode: Bool = false,
        onPageChange: ((Int, Int) -> Void)? = nil,
        onPageRangeChange: ((Int, Int, Int) -> Void)? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.isBookMode = isBookMode
        self.onPageChange = onPageChange
        self.onPageRangeChange = onPageRangeChange
        self.onTap = onTap
        super.init()
    }
    
    /// Attaches delegate, gestures, and notification center observers to the specified `PDFView`.
    ///
    /// - Parameter pdfView: The PDFView instance to configure.
    func attach(to pdfView: PDFView) {
        self.pdfView = pdfView
        pdfView.delegate = self
        
        detachObservers()
        
        pageObservationTask = Task { @MainActor [weak self, weak pdfView] in
            for await _ in NotificationCenter.default.notifications(named: .PDFViewPageChanged, object: pdfView) {
                guard let self else { return }
                self.updatePageInfo()
            }
        }
        
        scaleObservationTask = Task { @MainActor [weak self, weak pdfView] in
            for await _ in NotificationCenter.default.notifications(named: .PDFViewScaleChanged, object: pdfView) {
                guard let self else { return }
                self.updateScrollState()
            }
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        pdfView.addGestureRecognizer(tapGesture)
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = self
        pdfView.addGestureRecognizer(pan)
        self.panGesture = pan
        
        updateScrollState()
        
        Task { @MainActor [weak self] in
            self?.updatePageInfo()
        }
    }
    
    /// Cancels active notification observation tasks.
    private func detachObservers() {
        pageObservationTask?.cancel()
        pageObservationTask = nil
        scaleObservationTask?.cancel()
        scaleObservationTask = nil
    }
    
    /// Detaches all gestures, delegates, and observers when the view is dismantled.
    func detach() {
        detachObservers()
        if let panGesture, let pdfView {
            pdfView.removeGestureRecognizer(panGesture)
            self.panGesture = nil
        }
        if let pdfView {
            pdfView.delegate = nil
            self.pdfView = nil
        }
    }
    
    /// Adjusts scrolling capability on the internal scroll view based on zoom factor.
    func updateScrollState() {
        guard let pdfView else { return }
        if isBookMode {
            let isZoomed = pdfView.scaleFactor > (pdfView.minScaleFactor + 0.05)
            internalScrollView?.isScrollEnabled = isZoomed
        } else {
            internalScrollView?.isScrollEnabled = true
        }
    }
    
    /// Reads visible page indices from `pdfView.visiblePages` and dispatches page update callbacks.
    func updatePageInfo() {
        guard let pdfView = self.pdfView, let doc = pdfView.document else { return }
        let total = doc.pageCount
        let visibleIndices = pdfView.visiblePages.compactMap { doc.index(for: $0) }.sorted()
        
        let firstPage: Int
        let lastPage: Int
        if let first = visibleIndices.first, let last = visibleIndices.last {
            firstPage = first + 1
            lastPage = last + 1
        } else if let page = pdfView.currentPage {
            let idx = doc.index(for: page) + 1
            firstPage = idx
            lastPage = idx
        } else {
            firstPage = 1
            lastPage = 1
        }
        
        onPageChange?(firstPage, total)
        onPageRangeChange?(firstPage, lastPage, total)
    }
    
    /// Navigates directly to a target zero-based page index in the document.
    ///
    /// - Parameter index: Target zero-based page index.
    func goToPage(index: Int) {
        guard let pdfView, let doc = pdfView.document else { return }
        guard index >= 0, index < doc.pageCount, let page = doc.page(at: index) else { return }
        pdfView.go(to: page)
        updatePageInfo()
    }
    
    /// Advances forward to the next page or facing spread with a minimum 250ms debounce and haptic pulse.
    func goToNext() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPageTurnTime > 0.25 else { return }
        
        guard let pdfView, let doc = pdfView.document else { return }
        if isBookMode {
            let visibleIndices = pdfView.visiblePages.compactMap { doc.index(for: $0) }.sorted()
            let highest = visibleIndices.last ?? (pdfView.currentPage.flatMap { doc.index(for: $0) } ?? 0)
            let nextIndex = highest + 1
            if nextIndex < doc.pageCount, let page = doc.page(at: nextIndex) {
                lastPageTurnTime = now
                pdfView.go(to: page)
                updatePageInfo()
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                return
            }
        }
        if pdfView.canGoToNextPage {
            lastPageTurnTime = now
            pdfView.goToNextPage(nil)
            updatePageInfo()
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }
    
    /// Regresses backward to the preceding page or facing spread with a minimum 250ms debounce and haptic pulse.
    func goToPrevious() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPageTurnTime > 0.25 else { return }
        
        guard let pdfView, let doc = pdfView.document else { return }
        if isBookMode {
            let visibleIndices = pdfView.visiblePages.compactMap { doc.index(for: $0) }.sorted()
            let lowest = visibleIndices.first ?? (pdfView.currentPage.flatMap { doc.index(for: $0) } ?? 0)
            if lowest > 0 {
                let targetIndex: Int
                if lowest == 1 && pdfView.displaysAsBook {
                    targetIndex = 0
                } else {
                    targetIndex = max(0, lowest - 2)
                }
                if let page = doc.page(at: targetIndex) {
                    lastPageTurnTime = now
                    pdfView.go(to: page)
                    updatePageInfo()
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    return
                }
            }
        }
        if pdfView.canGoToPreviousPage {
            lastPageTurnTime = now
            pdfView.goToPreviousPage(nil)
            updatePageInfo()
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }
    
    /// Pan gesture handler detecting horizontal finger swipes in book mode to flip pages.
    @objc func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
        guard isBookMode else { return }
        guard let pdfView, pdfView.scaleFactor <= pdfView.minScaleFactor + 0.05 else { return }
        
        switch recognizer.state {
        case .ended:
            let translation = recognizer.translation(in: pdfView)
            let velocity = recognizer.velocity(in: pdfView)
            
            guard abs(translation.x) > abs(translation.y) else { return }
            
            let distanceThreshold: CGFloat = 30.0
            let velocityThreshold: CGFloat = 200.0
            
            if translation.x < -distanceThreshold || velocity.x < -velocityThreshold {
                goToNext()
            } else if translation.x > distanceThreshold || velocity.x > velocityThreshold {
                goToPrevious()
            }
        default:
            break
        }
    }
    
    /// Single tap action handler triggering HUD visibility toggle.
    @objc func handleSingleTap() {
        onTap?()
    }
    
    /// Allows simultaneous gesture recognition with system navigation gestures.
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
