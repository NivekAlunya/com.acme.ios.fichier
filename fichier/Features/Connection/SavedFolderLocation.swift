//
//  SavedFolderLocation.swift
//  fichier
//

import Foundation

nonisolated public struct SavedFolderLocation: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let bookmarkData: Data
    public let isICloud: Bool
    public let dateAdded: Date
    
    nonisolated public init(
        id: String = UUID().uuidString,
        name: String,
        bookmarkData: Data,
        isICloud: Bool,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
        self.isICloud = isICloud
        self.dateAdded = dateAdded
    }
}
