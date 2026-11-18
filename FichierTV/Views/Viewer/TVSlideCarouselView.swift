//
//  TVSlideCarouselView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Slide-style image strip whose motion is derived purely from index distance.
///
/// Every slide is positioned at `(slideIndex - currentIndex) × width`, so one animated index change moves
/// all slides together. The exit and entry edges follow from the index difference at render time, which
/// removes any dependency on a stored transition direction (and on stale transitions of removed views).
struct TVSlideCarouselView: View {
    /// Ordered items of the viewer.
    let items: [MediaSourceItem]

    /// Index of the displayed item.
    let currentIndex: Int

    /// Full-resolution image of the displayed item, when loaded.
    let currentImage: UIImage?

    /// Cache lookup for neighbouring slides.
    let cachedImage: (String) -> UIImage?

    /// Current slide plus its direct neighbours.
    private var visibleIndices: [Int] {
        guard !items.isEmpty else { return [] }
        let lower = max(0, currentIndex - 1)
        let upper = min(items.count - 1, currentIndex + 1)
        guard lower <= upper else { return [] }
        return Array(lower...upper)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(visibleIndices, id: \.self) { index in
                    let item = items[index]
                    TVSlideImageView(
                        item: item,
                        image: index == currentIndex ? (currentImage ?? cachedImage(item.id)) : cachedImage(item.id)
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .offset(x: CGFloat(index - currentIndex) * proxy.size.width)
                    .transition(.identity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
    }
}
