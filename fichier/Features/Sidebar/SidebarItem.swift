//
//  SidebarItem.swift
//  fichier
//

import Foundation
import FichierKit

/// Item displayed in the root navigation locations sidebar list.
///
/// Encapsulates storage locations (Photos, Local, iCloud, SMB) and dynamic shares discovered under a connected SMB server.
public enum SidebarItem: Identifiable, Hashable, Sendable {
    /// Top-level storage location root (e.g. Apple Photos, Local Documents, iCloud Drive, or SMB Server).
    case location(StorageLocation)
    
    /// Remote SMB share source discovered beneath the currently connected server.
    case share(MediaItem)
    
    /// Unique stable identifier across storage locations and child shares.
    public var id: String {
        switch self {
        case .location(let location):
            return "loc_\(location.id)"
        case .share(let item):
            return "share_\(item.id)"
        }
    }
}
