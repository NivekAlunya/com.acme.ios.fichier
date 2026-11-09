//
//  TVServerFormMode.swift
//  FichierTV
//

import Foundation
import FichierKit

/// Operational mode for the SMB server configuration form.
public enum TVServerFormMode: Hashable, Sendable {
    case add
    case edit(SavedSMBConnection)
}
