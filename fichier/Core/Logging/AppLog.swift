//
//  AppLog.swift
//  fichier
//

@_exported import OSLog

/// Centralized unified logging namespace for the entire application.
///
/// ### Architecture & Concurrency
/// - **Actor Isolation**: Explicitly marked `nonisolated enum` without cases (acting as an uninstantiable namespace),
///   allowing concurrent calls from any actor, task, or background queue without synchronization overhead.
/// - **Privacy & Diagnostics**: File names, network addresses, and sensitive paths should always be logged
///   with `privacy: .private` or `.sensitive` to ensure redaction in release builds and system diagnostic profiles.
nonisolated enum AppLog {
    
    /// The application bundle identifier used to categorize unified logging subsystems in Console.app.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.acme.ios.fichier"
    
    /// Unified logger dedicated to SMB network protocols, socket operations, file downloads, and tree listings.
    static let smb = Logger(subsystem: subsystem, category: "smb")
    
    /// Unified logger dedicated to NetService / Bonjour / mDNS network host discovery on the local network.
    static let discovery = Logger(subsystem: subsystem, category: "discovery")
    
    /// Unified logger dedicated to video playback, AVPlayer lifecycle, streaming resource loaders, and seek operations.
    static let player = Logger(subsystem: subsystem, category: "player")
    
    /// Unified logger dedicated to PhotoKit authorization, asset creation, and library export tasks.
    static let photos = Logger(subsystem: subsystem, category: "photos")
    
    /// Unified logger dedicated to Keychain credential storage, password lookups, and security query execution.
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
}
