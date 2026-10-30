//
//  AppLog.swift
//  fichier
//

import OSLog

/// Centralized loggers. File names and paths are logged with `privacy: .private`
/// so they are redacted in release logs and sysdiagnose.
nonisolated enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.acme.ios.fichier"
    
    static let smb = Logger(subsystem: subsystem, category: "smb")
    static let discovery = Logger(subsystem: subsystem, category: "discovery")
    static let player = Logger(subsystem: subsystem, category: "player")
    static let photos = Logger(subsystem: subsystem, category: "photos")
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
}
