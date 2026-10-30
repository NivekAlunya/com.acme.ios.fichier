//
//  SMBKeychain.swift
//  fichier
//

import Foundation
import Security
import OSLog

nonisolated enum SMBKeychain {
    private static let service = "com.acme.ios.photos.smb"
    
    private static func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
    
    /// Stores the password atomically. The item is only readable while the device is unlocked,
    /// never leaves this device (no backup / device migration) and is never synced to iCloud Keychain.
    /// Existing items are upgraded to these attributes on the next save.
    @discardableResult
    static func savePassword(_ password: String, for account: String) -> Bool {
        let query = baseQuery(for: account)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        
        if status != errSecSuccess {
            AppLog.keychain.error("Failed to save password (OSStatus \(status))")
        }
        return status == errSecSuccess
    }
    
    static func loadPassword(for account: String) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                AppLog.keychain.error("Failed to load password (OSStatus \(status))")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    static func deletePassword(for account: String) {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLog.keychain.error("Failed to delete password (OSStatus \(status))")
        }
    }
}
