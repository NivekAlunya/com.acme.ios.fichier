//
//  StorageLocationNotification.swift
//  fichier
//

import Foundation

extension Notification.Name {
    /// Notification posted to request all active storage workers purge in-memory caches.
    public static let clearAllMemoryCaches = Notification.Name("com.acme.ios.fichier.clearAllMemoryCaches")
}
