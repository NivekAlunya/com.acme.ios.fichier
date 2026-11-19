//
//  TVBrowserFocusTarget.swift
//  FichierTV
//
//

import Foundation

/// Focus targets for remote navigation within `TVMediaBrowserView`.
public enum TVBrowserFocusTarget: Hashable, Sendable {
    case item(String)
    case sort
    case grid
    case list
}
