//
//  TVSlideImageView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Renders a single slide image during full-screen tvOS viewing, decoupling the slide's visual
/// state from live coordinator mutations during asymmetric SwiftUI transitions.
public struct TVSlideImageView: View {
    public let item: MediaSourceItem
    public let image: UIImage?

    public init(item: MediaSourceItem, image: UIImage?) {
        self.item = item
        self.image = image
    }

    public var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TVThumbnailView(item: item, targetSize: CGSize(width: 1920, height: 1080))
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
