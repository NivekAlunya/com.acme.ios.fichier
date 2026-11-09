//
//  TVSeekThumbnailState.swift
//  FichierTV
//
//

import UIKit

/// UI state backing the floating seek thumbnail preview card during holds and scrubbing.
public struct TVSeekThumbnailState: Equatable, Sendable {
    public let targetTime: Double
    public let bucketTime: Double
    public let image: UIImage?
    public let isLoading: Bool

    public init(targetTime: Double, bucketTime: Double, image: UIImage?, isLoading: Bool) {
        self.targetTime = targetTime
        self.bucketTime = bucketTime
        self.image = image
        self.isLoading = isLoading
    }

    public static func == (lhs: TVSeekThumbnailState, rhs: TVSeekThumbnailState) -> Bool {
        lhs.targetTime == rhs.targetTime &&
        lhs.bucketTime == rhs.bucketTime &&
        lhs.isLoading == rhs.isLoading &&
        lhs.image === rhs.image
    }
}
