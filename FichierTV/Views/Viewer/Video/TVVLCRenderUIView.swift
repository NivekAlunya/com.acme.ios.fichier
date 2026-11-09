//
//  TVVLCRenderUIView.swift
//  FichierTV
//
//

import UIKit

/// Container `UIView` pinning `TVVLCPlayerEngine.renderView` to its bounds without intercepting Siri Remote focus.
///
/// NOTE: UIKit view is utilized here because SwiftUI on tvOS does not provide an equivalent drawable
/// surface for `VLCMediaPlayer.drawable`.
public final class TVVLCRenderUIView: UIView {
    private weak var mountedRenderView: UIView?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Embeds the engine's render surface filling the container edge-to-edge.
    public func mountRenderView(_ renderView: UIView) {
        guard mountedRenderView !== renderView else { return }
        mountedRenderView?.removeFromSuperview()

        renderView.removeFromSuperview()
        renderView.translatesAutoresizingMaskIntoConstraints = false
        renderView.isUserInteractionEnabled = false
        addSubview(renderView)

        NSLayoutConstraint.activate([
            renderView.topAnchor.constraint(equalTo: topAnchor),
            renderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            renderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            renderView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        mountedRenderView = renderView
    }
}
