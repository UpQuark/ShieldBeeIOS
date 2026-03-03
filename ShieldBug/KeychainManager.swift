//
//  KeychainManager.swift
//  ShieldBug
//

import CryptoKit
import Foundation
import Security

enum KeychainManager {
    private static let service = "shieldbug.ShieldBug"
    private static let pinAccount = "pin_hash"

    static var hasPin: Bool { retrieve(account: pinAccount) != nil }

    static func savePin(_ pin: String) {
        let hash = Data(SHA256.hash(data: Data(pin.utf8)))
        store(data: hash, account: pinAccount)
    }

    static func verifyPin(_ pin: String) -> Bool {
        guard let stored = retrieve(account: pinAccount) else { return false }
        return stored == Data(SHA256.hash(data: Data(pin.utf8)))
    }

    static func clearPin() { delete(account: pinAccount) }

    // MARK: - Private helpers

    private static func store(data: Data, account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func retrieve(account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    private static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
