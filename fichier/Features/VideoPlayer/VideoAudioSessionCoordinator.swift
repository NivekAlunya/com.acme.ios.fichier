//
//  VideoAudioSessionCoordinator.swift
//  fichier
//

import AVFoundation
import Wappn

/// Coordinator managing system `AVAudioSession` configuration for media playback.
public enum VideoAudioSessionCoordinator: Sendable {
    /// Configures and activates the system audio session for video playback in the background.
    public static func activatePlaybackSession() {
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
            } catch {
                loge("Failed to activate audio session: \(error.localizedDescription)")
            }
        }
    }

    /// Releases the active audio session asynchronously.
    public static func deactivateSession() {
        Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
