//
//  TVSeekThumbnailRequest.swift
//  FichierTV
//
//

import CoreGraphics
import Foundation
import FichierKit

/// Request parameters identifying a quantized preview frame extraction target.
public struct TVSeekThumbnailRequest: Equatable, Sendable {
    public let url: URL
    public let assetKey: String
    public let targetTime: Double
    public let duration: Double
    public let engineKind: PlayerEngineKind
    public let maxDimension: CGFloat
    public let vlcOptions: VLCPlaybackOptions?

    public init(
        url: URL,
        assetKey: String,
        targetTime: Double,
        duration: Double,
        engineKind: PlayerEngineKind,
        maxDimension: CGFloat = 360,
        vlcOptions: VLCPlaybackOptions? = nil
    ) {
        self.url = url
        self.assetKey = assetKey
        self.targetTime = targetTime
        self.duration = duration
        self.engineKind = engineKind
        self.maxDimension = maxDimension
        self.vlcOptions = vlcOptions
    }
}
