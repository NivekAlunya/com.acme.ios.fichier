//
//  TVRootSection.swift
//  FichierTV
//

import Foundation

/// Top-level sections available in the tvOS navigation bar.
public enum TVRootSection: String, CaseIterable, Identifiable, Sendable {
    case photos = "Photos"
    case shares = "Shares"

    public var id: String { rawValue }
}
