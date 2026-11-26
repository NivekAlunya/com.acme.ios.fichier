//
//  VideoAudioSessionCoordinator.swift
//  fichier
//

import AVFoundation
import Wappn

/// Actor-isolated coordinator serializing system `AVAudioSession` activation and deactivation for media playback.
public actor VideoAudioSessionCoordinator {
    public static let shared = VideoAudioSessionCoordinator()

    @MainActor
    private static var pendingTransitionTask: Task<Void, Never>?

    private init() {}

    /// Enqueues playback audio session activation in strict FIFO order from the main actor.
    @MainActor
    public static func enqueuePlaybackSessionActivation() {
        let previous = pendingTransitionTask
        pendingTransitionTask = Task {
            _ = await previous?.value
            await shared.activatePlaybackSession()
        }
    }

    /// Enqueues audio session deactivation in strict FIFO order from the main actor.
    @MainActor
    public static func enqueueSessionDeactivation() {
        let previous = pendingTransitionTask
        pendingTransitionTask = Task {
            _ = await previous?.value
            await shared.deactivateSession()
        }
    }

    /// Configures and activates the system audio session for video playback.
    public func activatePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            loge("Failed to activate audio session: \(error.localizedDescription)")
        }
    }

    /// Releases the active audio session.
    public func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logw("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
}
