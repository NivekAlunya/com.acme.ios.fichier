//
//  StorageLocationConnectionState.swift
//  fichier
//
//

import Foundation

/// Discrete connection lifecycle states for `StorageLocationManager`.
public enum StorageLocationConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case failed(String)
}
