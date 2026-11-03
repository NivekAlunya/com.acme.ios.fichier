//
//  PDFKitCoordinator.swift
//  fichier
//

import UIKit
import PDFKit

@MainActor
final class PDFKitCoordinator: NSObject, PDFViewDelegate, UIGestureRecognizerDelegate {
    weak var pdfView: PDFView?
    var onPageChange: ((Int, Int) -> Void)?
    var onTap: (() -> Void)?
    private var pageObserver: (any NSObjectProtocol)?
    
    init(onPageChange: ((Int, Int) -> Void)? = nil, onTap: (() -> Void)? = nil) {
        self.onPageChange = onPageChange
        self.onTap = onTap
        super.init()
    }
    
    func attach(to pdfView: PDFView) {
        self.pdfView = pdfView
        pdfView.delegate = self
        
        if let pageObserver {
            NotificationCenter.default.removeObserver(pageObserver)
            self.pageObserver = nil
        }
        
        pageObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePageInfo()
            }
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        pdfView.addGestureRecognizer(tapGesture)
        
        updatePageInfo()
    }
    
    func detach() {
        if let pageObserver {
            NotificationCenter.default.removeObserver(pageObserver)
            self.pageObserver = nil
        }
        if let pdfView {
            pdfView.delegate = nil
            self.pdfView = nil
        }
    }
    
    func updatePageInfo() {
        guard let pdfView = self.pdfView, let doc = pdfView.document else { return }
        let total = doc.pageCount
        let current: Int
        if let page = pdfView.currentPage {
            current = doc.index(for: page) + 1
        } else {
            current = 1
        }
        onPageChange?(current, total)
    }
    
    @objc func handleSingleTap() {
        onTap?()
    }
    
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
    
    deinit {
        if let pageObserver {
            NotificationCenter.default.removeObserver(pageObserver)
        }
    }
}
