//
//  StorageLocationKind.swift
//  fichier
//

import Foundation

public enum StorageLocationKind: String, Codable, Hashable, Sendable {
    case smb
    case localFolder
    case iCloudFolder
}
