//
//  StorageLocation.swift
//  fichier
//

import SwiftUI
import FichierKit

/// Represents a unified storage root displayed in the sidebar and navigation views.
///
/// `StorageLocation` abstracts distinct storage backends (SMB file shares, local file system folders,
/// iCloud Drive directories, and the system Photos library) into a unified identity model.
nonisolated public struct StorageLocation: Identifiable, Hashable, Sendable {
    /// Unique identifier for the storage location (e.g. `photos::library`, `smb::user@host`, `local::UUID`).
    public let id: String
    
    /// User-facing display title for this storage location.
    public let name: String
    
    /// Optional explanatory secondary text, such as the username, cloud indicator, or device status.
    public let subtitle: String?
    
    /// The underlying storage provider kind.
    public let kind: StorageLocationKind
    
    /// Associated validated connection metadata when `kind == .smb`.
    public let smbConnection: SavedSMBConnection?
    
    /// Associated security-scoped folder bookmark metadata when `kind == .localFolder` or `.iCloudFolder`.
    public let folderLocation: SavedFolderLocation?
    
    /// Well-known constant identifier representing the system Photo Library location.
    public static let photosLocationID = "photos::library"
    
    /// Singleton location representing the system Apple Photos library.
    nonisolated public static var photos: StorageLocation {
        StorageLocation(
            id: photosLocationID,
            name: String(localized: .Strings.sidebarLocationPhotos),
            subtitle: String(localized: .Strings.sidebarLocationPhotoLibrary),
            kind: .photos,
            smbConnection: nil,
            folderLocation: nil
        )
    }
    
    /// Designated memberwise initializer.
    ///
    /// - Parameters:
    ///   - id: Unique location identifier.
    ///   - name: User-facing display name.
    ///   - subtitle: Optional secondary description.
    ///   - kind: Provider kind.
    ///   - smbConnection: Optional SMB metadata.
    ///   - folderLocation: Optional local folder metadata.
    nonisolated public init(
        id: String,
        name: String,
        subtitle: String?,
        kind: StorageLocationKind,
        smbConnection: SavedSMBConnection? = nil,
        folderLocation: SavedFolderLocation? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.kind = kind
        self.smbConnection = smbConnection
        self.folderLocation = folderLocation
    }
    
    /// Convenience initializer creating a location from an authenticated SMB connection record.
    ///
    /// - Parameter smb: The persisted SMB connection configuration.
    nonisolated public init(smb: SavedSMBConnection) {
        self.id = "smb::\(smb.id)"
        self.name = smb.displayName
        self.subtitle = smb.username
        self.kind = .smb
        self.smbConnection = smb
        self.folderLocation = nil
    }
    
    /// Convenience initializer creating a location from a saved local or iCloud folder bookmark.
    ///
    /// - Parameter folder: The persisted folder location record.
    nonisolated public init(folder: SavedFolderLocation) {
        self.id = folder.isICloud ? "icloud::\(folder.id)" : "local::\(folder.id)"
        self.name = folder.name
        self.subtitle = folder.isICloud ? String(localized: .Strings.sidebarLocationIcloudDrive) : String(localized: .Strings.sidebarLocationOnDevice)
        self.kind = folder.isICloud ? .iCloudFolder : .localFolder
        self.smbConnection = nil
        self.folderLocation = folder
    }
    
    /// The SF Symbol icon name representing this location on the current platform.
    @MainActor
    public var systemIcon: String {
        switch kind {
        case .smb:
            return "macmini.fill"
        case .localFolder:
            #if os(iOS)
            return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
            #else
            return "internaldrive.fill"
            #endif
        case .iCloudFolder:
            return "icloud.fill"
        case .photos:
            return "photo.on.rectangle.angled"
        }
    }
    
    /// The accent color associated with this storage provider kind in the sidebar UI.
    @MainActor
    public var iconColor: Color {
        switch kind {
        case .smb:
            return .blue
        case .localFolder:
            return .orange
        case .iCloudFolder:
            return .teal
        case .photos:
            return .pink
        }
    }
}
