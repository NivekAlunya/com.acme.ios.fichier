//
//  PDFPageCanvasRepresentable.swift
//  fichier
//

#if !os(tvOS)
import SwiftUI
import PDFKit

/// SwiftUI wrapper embedding `PDFPageCanvasView` for standalone vector page rendering.
///
/// Encapsulates UIView lifecycle, delegating page assignments and redrawing efficiently
/// without reallocating underlying drawing contexts when the page reference remains identical.
public struct PDFPageCanvasRepresentable: UIViewRepresentable {
    /// Active PDFKit page to render.
    public let page: PDFPage
    
    /// Designated public initializer.
    ///
    /// - Parameter page: PDFKit page reference.
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

#endif // !os(tvOS)
