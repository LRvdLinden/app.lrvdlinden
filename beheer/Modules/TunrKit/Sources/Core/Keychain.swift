import Foundation
import Security

/// Sessietoken in de Keychain: alleen op dit apparaat (niet in de iCloud-sleutelhanger, niet naar een ander toestel).
/// Op de Mac de data-protection-Keychain (zoals iOS); lukt dat niet (bv. een build zonder ondertekening), dan de
/// gewone Keychain van de gebruiker.
enum Keychain {
    private static let service = "nl.lrvdlinden.tunr.beheer"

    private static func base(_ account: String, dataProtection: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        #if os(macOS)
        if dataProtection {
            q[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue as Any
        }
        #endif
        return q
    }

    private static var variants: [Bool] {
        #if os(macOS)
        return [true, false]
        #else
        return [true]
        #endif
    }

    static func read(_ account: String) -> Data? {
        for dp in variants {
            var q = base(account, dataProtection: dp)
            q[kSecReturnData as String] = kCFBooleanTrue as Any
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data {
                return data
            }
        }
        return nil
    }

    @discardableResult
    static func write(_ account: String, _ data: Data) -> Bool {
        delete(account)
        for dp in variants {
            var q = base(account, dataProtection: dp)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            if SecItemAdd(q as CFDictionary, nil) == errSecSuccess { return true }
        }
        return false
    }

    static func delete(_ account: String) {
        for dp in variants {
            SecItemDelete(base(account, dataProtection: dp) as CFDictionary)
        }
    }
}
