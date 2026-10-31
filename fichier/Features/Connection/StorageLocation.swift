//
//  StorageLocation.swift
//  fichier
//

import SwiftUI

nonisolated public struct StorageLocation: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String?
    public let kind: StorageLocationKind
    public let smbConnection: SavedSMBConnection?
    public let folderLocation: SavedFolderLocation?
    
    nonisolated public init(smb: SavedSMBConnection) {
        self.id = "smb::\(smb.id)"
        self.name = smb.displayName
        self.subtitle = smb.username
        self.kind = .smb
        self.smbConnection = smb
        self.folderLocation = nil
    }
    
    nonisolated public init(folder: SavedFolderLocation) {
        self.id = folder.isICloud ? "icloud::\(folder.id)" : "local::\(folder.id)"
        self.name = folder.name
        self.subtitle = folder.isICloud ? String(localized: .Strings.sidebarLocationIcloudDrive) : String(localized: .Strings.sidebarLocationOnDevice)
        self.kind = folder.isICloud ? .iCloudFolder : .localFolder
        self.smbConnection = nil
        self.folderLocation = folder
    }
    
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
        }
    }
    
    @MainActor
    public var iconColor: Color {
        switch kind {
        case .smb:
            return .blue
        case .localFolder:
            return .orange
        case .iCloudFolder:
            return .teal
        }
    }
}
