//
//  TVRemoteSeekPreview.swift
//  FichierTV
//
//

import Foundation

/// Live or just-committed seek preview displayed while holding or tapping rewind/fast-forward.
public struct TVRemoteSeekPreview: Equatable, Sendable {
    public let targetTime: Double
    public let deltaSeconds: Double
    public let isHolding: Bool

    public init(targetTime: Double, deltaSeconds: Double, isHolding: Bool) {
        self.targetTime = targetTime
        self.deltaSeconds = deltaSeconds
        self.isHolding = isHolding
    }

    public var isForward: Bool {
        deltaSeconds >= 0
    }
}
