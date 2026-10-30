//
//  VideoTrackOption.swift
//  fichier
//

import AVFoundation

public struct VideoTrackOption: Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let mediaOption: AVMediaSelectionOption?
    
    public init(id: String, displayName: String, mediaOption: AVMediaSelectionOption?) {
        self.id = id
        self.displayName = displayName
        self.mediaOption = mediaOption
    }
}
