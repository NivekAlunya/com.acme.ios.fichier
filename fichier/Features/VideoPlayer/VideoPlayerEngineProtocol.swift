//
//  VideoPlayerEngineProtocol.swift
//  fichier
//

import Foundation

/// Unified abstraction defining the core playback, seeking, volume, and lifecycle contract across video backends.
///
/// Both `NativePlayerEngine` (AVFoundation) and `ExtendedPlayerEngine` (MobileVLCKit) conform
/// to this protocol, enabling `VideoPlayerController` and the SwiftUI HUD to remain backend-agnostic.
@MainActor
public protocol VideoPlayerEngineProtocol: AnyObject, Sendable {
    /// The architectural category of this playback engine.
    var engineKind: VideoEngineKind { get }
    
    /// Indicates whether media playback is actively proceeding.
    var isPlaying: Bool { get }
    
    /// Current playback timestamp in seconds.
    var currentTimeSeconds: Double { get }
    
    /// Total duration of the currently mounted media in seconds (finite or 0 if unknown/streaming).
    var durationSeconds: Double { get }
    
    /// Normalized audio volume level between `0.0` and `1.0`.
    var volume: Double { get set }
    
    /// Indicates whether audio output is currently suppressed.
    var isMuted: Bool { get set }
    
    /// Active playback speed multiplier.
    var playbackRate: VideoPlaybackRate { get set }
    
    /// Resumes or starts media playback.
    func play()
    
    /// Pauses active media playback.
    func pause()
    
    /// Asynchronously seeks to the target timestamp with precision tolerances.
    ///
    /// - Parameters:
    ///   - seconds: The target time in seconds.
    ///   - toleranceBefore: Acceptable time tolerance prior to target.
    ///   - toleranceAfter: Acceptable time tolerance after target.
    ///   - completion: Optional callback executed when seek completes.
    func seek(
        to seconds: Double,
        toleranceBefore: Double,
        toleranceAfter: Double,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    )
    
    /// Immediately halts playback and deallocates native/player resources.
    func tearDown()
}
