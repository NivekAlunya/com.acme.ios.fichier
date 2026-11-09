//
//  TVSeekThumbnailPreviewCardView.swift
//  FichierTV
//
//

import SwiftUI

/// Non-focusable floating 16:9 thumbnail preview card positioned along the video timeline.
public struct TVSeekThumbnailPreviewCardView: View {
    public let thumbnailState: TVSeekThumbnailState
    public let duration: Double
    public let detailLabel: String?

    public init(
        thumbnailState: TVSeekThumbnailState,
        duration: Double,
        detailLabel: String? = nil
    ) {
        self.thumbnailState = thumbnailState
        self.duration = duration
        self.detailLabel = detailLabel
    }

    private var progressRatio: Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, thumbnailState.targetTime / duration))
    }

    private var timestampLabel: String {
        TVRemoteSeekCalculator.formattedTimestamp(thumbnailState.targetTime)
    }

    public var body: some View {
        let cardWidth: CGFloat = 296
        let imageHeight: CGFloat = 166

        GeometryReader { proxy in
            let halfCard = cardWidth * 0.5
            let rawCenter = proxy.size.width * progressRatio
            let centerX = min(max(halfCard, rawCenter), max(halfCard, proxy.size.width - halfCard))

            VStack(spacing: 8) {
                ZStack {
                    Color.black.opacity(0.86)

                    if let image = thumbnailState.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: cardWidth, height: imageHeight)
                            .clipped()
                    } else {
                        VStack(spacing: 10) {
                            if thumbnailState.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "film")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                    }

                    if thumbnailState.isLoading && thumbnailState.image != nil {
                        ProgressView()
                            .tint(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .frame(width: cardWidth, height: imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.55), radius: 14, y: 6)

                HStack(spacing: 8) {
                    Text(timestampLabel)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)

                    if let detailLabel, !detailLabel.isEmpty {
                        Text(detailLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .position(x: centerX, y: (imageHeight + 42) * 0.5)
        }
        .frame(height: imageHeight + 42)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }
}
