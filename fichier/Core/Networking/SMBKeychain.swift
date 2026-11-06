//
//  SMBKeychain.swift
//  fichier
//

import Foundation
import Security
import OSLog

/// Security service actor providing atomic, hardware-protected storage for SMB credentials using the Apple Keychain Services API.
///
/// ### Security Architecture
/// - **Actor Isolation**: All credential modifications and reads are strictly actor-isolated, ensuring zero data races across concurrent tasks and background threads.
/// - **Hardware Security**: Passwords are protected using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, ensuring that keys
///   remain encrypted when the device is locked and are excluded from iCloud backups, iTunes unencrypted backups, and device migration transfers.
/// - **Sync Disabled**: `kSecAttrSynchronizable = false` ensures credentials never leave the physical device over iCloud Keychain.
/// - **In-Memory Fallback**: In test and simulator environments lacking Keychain entitlements, an in-memory dictionary is isolated within this actor.
public actor SMBKeychain {

    /// Shared singleton instance.
    public static let shared = SMBKeychain()
    
    #if DEBUG
    private var inMemoryFallback: [String: String] = [:]
    #endif

    /// The Keychain service identifier partitioning application credentials from other system passwords.
    private let service = "com.acme.ios.photos.smb"

    public init() {}

    // MARK: - Static Asynchronous API

    /// Stores or updates an SMB password atomically within the secure Keychain enclave.
    ///
    /// - Parameters:
    ///   - password: The plaintext password string to encrypt and store as UTF-8 data.
    ///   - account: The unique identifier representing the authenticated server and user.
    /// - Returns: `true` if the item was successfully created or updated; `false` otherwise.
    @discardableResult
    public static func savePassword(_ password: String, for account: String) async -> Bool {
        await shared.savePassword(password, for: account)
    }

    /// Retrieves a stored password from the Keychain for the specified account.
    ///
    /// - Parameter account: The account identifier previously used to store credentials.
    /// - Returns: The decrypted UTF-8 password string, or `nil` if not found or inaccessible.
    public static func loadPassword(for account: String) async -> String? {
        await shared.loadPassword(for: account)
    }

    /// Removes the password associated with the specified account from the Keychain.
    ///
    /// - Parameter account: The account identifier whose stored credentials should be purged.
    public static func deletePassword(for account: String) async {
        await shared.deletePassword(for: account)
    }

    // MARK: - Actor-Isolated Instance API

    /// Constructs the foundational dictionary query matching an SMB account entry in the Keychain.
    ///
    /// - Parameter account: The unique account name or endpoint identifier (e.g., host/username pair).
    /// - Returns: A standard CoreFoundation-compatible dictionary targeting generic password items.
    private func baseQuery(for account: String) -> [String: Any] {
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
    public func savePassword(_ password: String, for account: String) -> Bool {
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
            #if DEBUG
            inMemoryFallback[account] = password
            return true
            #else
            return false
            #endif
        }
        #if DEBUG
        inMemoryFallback[account] = password
        #endif
        return true
    }
    
    /// Retrieves a stored password from the Keychain for the specified account.
    ///
    /// - Parameter account: The account identifier previously used to store credentials.
    /// - Returns: The decrypted UTF-8 password string, or `nil` if not found or inaccessible.
    public func loadPassword(for account: String) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            #if DEBUG
            if let fallback = inMemoryFallback[account] {
                return fallback
            }
            #endif
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
    public func deletePassword(for account: String) {
        #if DEBUG
        inMemoryFallback.removeValue(forKey: account)
        #endif
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLog.keychain.error("Failed to delete password (OSStatus \(status))")
        }
    }
}
