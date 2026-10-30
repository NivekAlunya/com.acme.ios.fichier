//
//  VideoPlaybackRecord.swift
//  fichier
//

import Foundation

public struct VideoPlaybackRecord: Codable, Sendable, Equatable {
    public var position: Double
    public var duration: Double
    public var isFinished: Bool
    
    public init(position: Double, duration: Double, isFinished: Bool = false) {
        self.position = position
        self.duration = duration
        self.isFinished = isFinished
    }
    
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return max(0.0, min(1.0, position / duration))
    }
}
