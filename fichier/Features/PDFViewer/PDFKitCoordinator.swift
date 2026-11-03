//
//  PDFKitCoordinator.swift
//  fichier
//

import UIKit
import PDFKit

@MainActor
final class PDFKitCoordinator: NSObject, PDFViewDelegate, UIGestureRecognizerDelegate {
    weak var pdfView: PDFView?
    var isBookMode: Bool = false
    var onPageChange: ((Int, Int) -> Void)?
    var onPageRangeChange: ((Int, Int, Int) -> Void)?
    var onTap: (() -> Void)?
    
    private nonisolated(unsafe) var pageObserver: (any NSObjectProtocol)?
    private nonisolated(unsafe) var scaleObserver: (any NSObjectProtocol)?
    private var panGesture: UIPanGestureRecognizer?
    private var lastPageTurnTime: TimeInterval = 0
    
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
    
    func attach(to pdfView: PDFView) {
        self.pdfView = pdfView
        pdfView.delegate = self
        
        detachObservers()
        
        pageObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePageInfo()
            }
        }
        
        scaleObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewScaleChanged,
            object: pdfView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateScrollState()
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
    
    private nonisolated func detachObservers() {
        if let pageObserver {
            NotificationCenter.default.removeObserver(pageObserver)
            self.pageObserver = nil
        }
        if let scaleObserver {
            NotificationCenter.default.removeObserver(scaleObserver)
            self.scaleObserver = nil
        }
    }
    
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
    
    func updateScrollState() {
        guard let pdfView else { return }
        if isBookMode {
            let isZoomed = pdfView.scaleFactor > (pdfView.minScaleFactor + 0.05)
            internalScrollView?.isScrollEnabled = isZoomed
        } else {
            internalScrollView?.isScrollEnabled = true
        }
    }
    
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
    
    func goToPage(index: Int) {
        guard let pdfView, let doc = pdfView.document else { return }
        guard index >= 0, index < doc.pageCount, let page = doc.page(at: index) else { return }
        pdfView.go(to: page)
        updatePageInfo()
    }
    
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
    
    @objc func handleSingleTap() {
        onTap?()
    }
    
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
    
    deinit {
        detachObservers()
    }
}
