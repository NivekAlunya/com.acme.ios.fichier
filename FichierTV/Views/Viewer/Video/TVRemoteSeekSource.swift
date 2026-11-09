//
//  TVRemoteSeekSource.swift
//  FichierTV
//
//

import Foundation

/// Input path that originated a remote fast-forward or rewind seek gesture.
public enum TVRemoteSeekSource: Hashable, Sendable {
    case siriRemoteDirection
    case hardwareMediaCommand
}
