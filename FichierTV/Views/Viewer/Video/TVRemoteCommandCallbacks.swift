//
//  TVRemoteCommandCallbacks.swift
//  FichierTV
//
//

import Foundation

/// Main-actor callbacks invoked by the active media-remote command bridge.
public struct TVRemoteCommandCallbacks: Sendable {
    public let onSeekBegan: @MainActor @Sendable (Bool, TimeInterval) -> Void
    public let onSeekEnded: @MainActor @Sendable (Bool, TimeInterval) -> Void
    public let onTapSkip: @MainActor @Sendable (Bool, TimeInterval) -> Void
    public let onPlay: @MainActor @Sendable () -> Void
    public let onPause: @MainActor @Sendable () -> Void
    public let onTogglePlayPause: @MainActor @Sendable (TimeInterval) -> Void

    public init(
        onSeekBegan: @escaping @MainActor @Sendable (Bool, TimeInterval) -> Void,
        onSeekEnded: @escaping @MainActor @Sendable (Bool, TimeInterval) -> Void,
        onTapSkip: @escaping @MainActor @Sendable (Bool, TimeInterval) -> Void,
        onPlay: @escaping @MainActor @Sendable () -> Void,
        onPause: @escaping @MainActor @Sendable () -> Void,
        onTogglePlayPause: @escaping @MainActor @Sendable (TimeInterval) -> Void
    ) {
        self.onSeekBegan = onSeekBegan
        self.onSeekEnded = onSeekEnded
        self.onTapSkip = onTapSkip
        self.onPlay = onPlay
        self.onPause = onPause
        self.onTogglePlayPause = onTogglePlayPause
    }
}
