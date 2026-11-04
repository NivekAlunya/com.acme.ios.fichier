//
//  SMBKeychain.swift
//  fichier
//

import Foundation
import Security
import OSLog

/// Security service wrapper providing atomic, hardware-protected storage for SMB credentials using the Apple Keychain Services API.
///
/// ### Security Architecture
/// - **Hardware Security**: Passwords are protected using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, ensuring that keys
///   remain encrypted when the device is locked and are excluded from iCloud backups, iTunes unencrypted backups, and device migration transfers.
/// - **Sync Disabled**: `kSecAttrSynchronizable = false` ensures credentials never leave the physical device over iCloud Keychain.
/// - **Concurrency**: Marked `nonisolated enum`, safe for concurrent queries across background actors and main thread UI workflows.
nonisolated enum SMBKeychain {
    
    /// The Keychain service identifier partitioning application credentials from other system passwords.
    private static let service = "com.acme.ios.photos.smb"
    
    /// Constructs the foundational dictionary query matching an SMB account entry in the Keychain.
    ///
    /// - Parameter account: The unique account name or endpoint identifier (e.g., host/username pair).
    /// - Returns: A standard CoreFoundation-compatible dictionary targeting generic password items.
    private static func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
    
    /// Stores or updates an SMB password atomically within the secure Keychain enclave.
    ///
    /// ### Complex Code Breakdown:
    /// - **Upsert Pattern**: First attempts `SecItemUpdate` using `baseQuery`. If the item does not exist (`errSecItemNotFound`),
    ///   it seamlessly falls back to `SecItemAdd` with merged attributes.
    /// - **Attribute Migration**: Re-saving an existing item automatically enforces `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`,
    ///   upgrading legacy credential entries to modern security baselines.
    ///
    /// - Parameters:
    ///   - password: The plaintext password string to encrypt and store as UTF-8 data.
    ///   - account: The unique identifier representing the authenticated server and user.
    /// - Returns: `true` if the item was successfully created or updated; `false` otherwise.
    @discardableResult
    static func savePassword(_ password: String, for account: String) -> Bool {
        let query = baseQuery(for: account)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        
        // Attempt atomic in-place update first
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            // Fall back to insertion when the item is registered for the first time
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        
        if status != errSecSuccess {
            AppLog.keychain.error("Failed to save password (OSStatus \(status))")
        }
        return status == errSecSuccess
    }
    
    /// Retrieves a stored password from the Keychain for the specified account.
    ///
    /// - Parameter account: The account identifier previously used to store credentials.
    /// - Returns: The decrypted UTF-8 password string, or `nil` if not found or inaccessible.
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
    
    /// Removes the password associated with the specified account from the Keychain.
    ///
    /// - Parameter account: The account identifier whose stored credentials should be purged.
    static func deletePassword(for account: String) {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLog.keychain.error("Failed to delete password (OSStatus \(status))")
        }
    }
}
