import Foundation
import Security

/// Inloggegevens van LRvdLinden en PixelForges (en het apparaat-id van de centrale push) in de Keychain:
/// alleen dit apparaat, niet in iCloud, alleen leesbaar als het toestel ontgrendeld is.
enum Keychain {
    private static let service = "app.lrvdlinden.lrbeheer"

    private static func base(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    static func read(_ account: String) -> Data? {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func write(_ account: String, _ data: Data) {
        delete(account)
        var q = base(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }

    static func readCodable<T: Decodable>(_ account: String, as: T.Type) -> T? {
        read(account).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    static func writeCodable<T: Encodable>(_ account: String, _ value: T) {
        if let d = try? JSONEncoder().encode(value) { write(account, d) }
    }
}
