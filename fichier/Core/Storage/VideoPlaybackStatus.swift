//
//  VideoPlaybackStatus.swift
//  fichier
//

import Foundation

public enum VideoPlaybackStatus: Sendable, Equatable {
    case unwatched
    case inProgress(progress: Double)
    case finished
}
