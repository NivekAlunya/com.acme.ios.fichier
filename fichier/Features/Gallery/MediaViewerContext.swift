//
//  MediaViewerContext.swift
//  fichier
//

import Foundation

/// Encapsulates a selected media item and its active filtered playlist/gallery context for full-screen presentation.
public struct MediaViewerContext: Identifiable, Sendable {
    /// The initially focused media item.
    public let item: MediaItem
    
    /// The filtered, sorted snapshot of media items present in the active view when this item was selected.
    public let contextItems: [MediaItem]
    
    /// Stable identifier corresponding to the focused item.
    public var id: String { item.id }
    
    public init(item: MediaItem, contextItems: [MediaItem]) {
        self.item = item
        self.contextItems = contextItems
    }
    
    /// Resolves the active playlist or gallery items matching a given predicate, guaranteeing inclusion of the focused `item`.
    public func resolvedItems(matching predicate: (MediaItem) -> Bool) -> [MediaItem] {
        let filtered = contextItems.filter(predicate)
        var result = filtered.isEmpty ? [item] : filtered
        if !result.contains(where: { $0.id == item.id }) {
            result.append(item)
        }
        return result
    }
}
