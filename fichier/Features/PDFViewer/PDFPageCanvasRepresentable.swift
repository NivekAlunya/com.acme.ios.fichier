//
//  PDFPageCanvasRepresentable.swift
//  fichier
//

import SwiftUI
import PDFKit

public struct PDFPageCanvasRepresentable: UIViewRepresentable {
    public let page: PDFPage
    
    public init(page: PDFPage) {
        self.page = page
    }
    
    public func makeUIView(context: Context) -> PDFPageCanvasView {
        let view = PDFPageCanvasView()
        view.page = page
        return view
    }
    
    public func updateUIView(_ uiView: PDFPageCanvasView, context: Context) {
        if uiView.page !== page {
            uiView.page = page
        }
    }
}
