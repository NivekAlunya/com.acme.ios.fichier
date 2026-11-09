//
//  TVRemoteCommandHandling.swift
//  FichierTV
//
//

import Foundation

/// Abstracts tvOS hardware/CEC media remote command registration (`<<`, `>>`, play, pause) for testability.
@MainActor
public protocol TVRemoteCommandHandling: AnyObject {
    func activate(callbacks: TVRemoteCommandCallbacks)
    func updateNowPlaying(title: String, currentTime: Double, duration: Double, isPlaying: Bool)
    func deactivate()
}
