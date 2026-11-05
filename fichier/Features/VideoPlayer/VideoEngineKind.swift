//
//  VideoEngineKind.swift
//  fichier
//

import Foundation

/// Identifies the playback engine responsible for rendering a specific media asset.
public enum VideoEngineKind: Sendable, Equatable {
    /// Apple AVFoundation native playback engine (AVPlayer / AVPlayerLayer) for standard Apple formats.
    case native
    
    /// Extended open-source decoding engine (MobileVLCKit / LibVLC) for open containers and non-Apple codecs.
    case extended
}
