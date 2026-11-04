//
//  PDFPageCanvasView.swift
//  fichier
//

import UIKit
import PDFKit

/// Custom UIKit view rendering a single PDF page directly into CoreGraphics with crisp vector fidelity.
///
/// ### Coordinate Flipping & Geometry Calculation
/// CoreGraphics operates in a Cartesian coordinate space where the origin `(0, 0)` is at the bottom-left,
/// whereas UIKit places the origin at the top-left. To draw the PDF page upright:
/// 1. Determines aspect-fit scale ratio between the `.cropBox` bounds and the target `rect`.
/// 2. Translates the context origin to `(originX, originY + targetHeight)`.
/// 3. Inverts the vertical coordinate axis with `scaleBy(x: scale, y: -scale)`.
/// 4. Invokes `page.draw(with: .cropBox, to: context)`.
public final class PDFPageCanvasView: UIView {
    /// Active PDFKit page reference. Updating this property triggers an immediate redraw (`setNeedsDisplay`).
    public var page: PDFPage? {
        didSet {
            setNeedsDisplay()
        }
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        isOpaque = false
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let page = self.page else { return }
        let box = page.bounds(for: .cropBox)
        guard box.width > 0, box.height > 0 else { return }
        
        let scaleX = rect.width / box.width
        let scaleY = rect.height / box.height
        let scale = min(scaleX, scaleY)
        
        let targetWidth = box.width * scale
        let targetHeight = box.height * scale
        let originX = (rect.width - targetWidth) / 2.0
        let originY = (rect.height - targetHeight) / 2.0
        let targetRect = CGRect(x: originX, y: originY, width: targetWidth, height: targetHeight)
        
        // Draw crisp paper background
        UIColor.white.setFill()
        context.fill(targetRect)
        
        context.saveGState()
        context.clip(to: targetRect)
        context.translateBy(x: originX, y: originY + targetHeight)
        context.scaleBy(x: scale, y: -scale)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
    }
}
