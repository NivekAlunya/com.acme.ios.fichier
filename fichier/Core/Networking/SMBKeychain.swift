//
//  SMBKeychain.swift
//  fichier
//

import Foundation
import Security

nonisolated enum SMBKeychain {
    private static let service = "com.acme.ios.photos.smb"
    
    private static func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
    
    static func savePassword(_ password: String, for account: String) {
        let data = Data(password.utf8)
        let query = baseQuery(for: account)
        SecItemDelete(query as CFDictionary)
        
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    static func loadPassword(for account: String) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    static func deletePassword(for account: String) {
        let query = baseQuery(for: account)
        SecItemDelete(query as CFDictionary)
    }
}
