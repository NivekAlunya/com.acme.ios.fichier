//
//  StorageLocationKind.swift
//  fichier
//

import Foundation

/// Defines the underlying storage provider kind for a storage location.
///
/// Distinguishes between network protocols, sandboxed local storage, cloud storage,
/// and system media libraries to determine appropriate security and access mechanisms.
public enum StorageLocationKind: String, Codable, Hashable, Sendable {
    /// Remote SMB network file server (CIFS / Samba share).
    case smb
    
    /// On-device sandboxed folder accessed via security-scoped bookmarks.
    case localFolder
    
    /// Cloud-synchronized iCloud Drive folder accessed via security-scoped bookmarks.
    case iCloudFolder
    
    /// Local Apple Photos media library accessed via PhotoKit.
    case photos
}
