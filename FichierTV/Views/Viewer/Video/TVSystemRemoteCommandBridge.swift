//
//  TVSystemRemoteCommandBridge.swift
//  FichierTV
//
//

import AVFoundation
import Foundation
import MediaPlayer
import UIKit

/// Integrates tvOS `MPRemoteCommandCenter`, `MPNowPlayingInfoCenter`, and `AVAudioSession`
/// so dedicated `<<` / `>>` hardware/CEC/IR remote buttons route cleanly into the custom player.
@MainActor
public final class TVSystemRemoteCommandBridge: TVRemoteCommandHandling {
    private var commandTokens: [(MPRemoteCommand, Any)] = []
    private var isActivated: Bool = false

    public init() {}

    public func activate(callbacks: TVRemoteCommandCallbacks) {
        deactivate()
        isActivated = true

        configureAudioSession()
        UIApplication.shared.beginReceivingRemoteControlEvents()

        let center = MPRemoteCommandCenter.shared()

        registerSeekCommand(center.seekForwardCommand, isForward: true, callbacks: callbacks)
        registerSeekCommand(center.seekBackwardCommand, isForward: false, callbacks: callbacks)

        center.skipForwardCommand.preferredIntervals = [
            NSNumber(value: TVRemoteSeekCalculator.singleTapSkipSeconds)
        ]
        registerSkipCommand(center.skipForwardCommand, isForward: true, callbacks: callbacks)

        center.skipBackwardCommand.preferredIntervals = [
            NSNumber(value: TVRemoteSeekCalculator.singleTapSkipSeconds)
        ]
        registerSkipCommand(center.skipBackwardCommand, isForward: false, callbacks: callbacks)

        registerSimpleCommand(center.playCommand) {
            Task { @MainActor in
                callbacks.onPlay()
            }
        }
        registerSimpleCommand(center.pauseCommand) {
            Task { @MainActor in
                callbacks.onPause()
            }
        }
        registerTimestampedCommand(center.togglePlayPauseCommand) { uptime in
            Task { @MainActor in
                callbacks.onTogglePlayPause(uptime)
            }
        }
    }

    public func updateNowPlaying(title: String, currentTime: Double, duration: Double, isPlaying: Bool) {
        guard isActivated else { return }

        let safeCurrent = (currentTime.isFinite && !currentTime.isNaN) ? max(0, currentTime) : 0
        let safeDuration = (duration.isFinite && !duration.isNaN && duration > 0) ? duration : 0

        let nowPlayingCenter = MPNowPlayingInfoCenter.default()
        nowPlayingCenter.nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: safeDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: safeCurrent,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        nowPlayingCenter.playbackState = isPlaying ? .playing : .paused
    }

    public func deactivate() {
        for (command, token) in commandTokens {
            command.removeTarget(token)
            command.isEnabled = false
        }
        commandTokens.removeAll()

        if isActivated {
            let nowPlayingCenter = MPNowPlayingInfoCenter.default()
            nowPlayingCenter.nowPlayingInfo = nil
            nowPlayingCenter.playbackState = .stopped
            UIApplication.shared.endReceivingRemoteControlEvents()
            isActivated = false
        }
    }

    private func configureAudioSession() {
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
            } catch {
                // Keep remote command registration active even if audio session fails in test hosts.
            }
        }
    }

    private func registerSeekCommand(
        _ command: MPRemoteCommand,
        isForward: Bool,
        callbacks: TVRemoteCommandCallbacks
    ) {
        command.isEnabled = true
        let token = command.addTarget { event in
            let receivedUptime = ProcessInfo.processInfo.systemUptime
            let seekType = (event as? MPSeekCommandEvent)?.type
            Task { @MainActor in
                switch seekType {
                case .beginSeeking:
                    callbacks.onSeekBegan(isForward, receivedUptime)
                case .endSeeking:
                    callbacks.onSeekEnded(isForward, receivedUptime)
                case nil:
                    callbacks.onTapSkip(isForward, receivedUptime)
                @unknown default:
                    callbacks.onTapSkip(isForward, receivedUptime)
                }
            }
            return .success
        }
        commandTokens.append((command, token))
    }

    private func registerSkipCommand(
        _ command: MPSkipIntervalCommand,
        isForward: Bool,
        callbacks: TVRemoteCommandCallbacks
    ) {
        command.isEnabled = true
        let token = command.addTarget { _ in
            let receivedUptime = ProcessInfo.processInfo.systemUptime
            Task { @MainActor in
                callbacks.onTapSkip(isForward, receivedUptime)
            }
            return .success
        }
        commandTokens.append((command, token))
    }

    private func registerSimpleCommand(
        _ command: MPRemoteCommand,
        action: @escaping @Sendable () -> Void
    ) {
        command.isEnabled = true
        let token = command.addTarget { _ in
            action()
            return .success
        }
        commandTokens.append((command, token))
    }

    private func registerTimestampedCommand(
        _ command: MPRemoteCommand,
        action: @escaping @Sendable (TimeInterval) -> Void
    ) {
        command.isEnabled = true
        let token = command.addTarget { _ in
            let receivedUptime = ProcessInfo.processInfo.systemUptime
            action(receivedUptime)
            return .success
        }
        commandTokens.append((command, token))
    }
}
