import Foundation
import Security

/// Minimal Keychain wrapper for the user's own Gemini API key. Stored as a generic-password item so
/// it persists across launches and stays out of source, UserDefaults, and unencrypted backups. The
/// key is the user's own — entered in Settings — never shipped in the app.
enum KeychainStore {
    private static let service = "com.eliasleon.quiver"
    private static let account = "GEMINI_API_KEY"

    /// The stored Gemini key, or `nil` if none. Setting `nil`/blank deletes it.
    static var geminiKey: String? {
        get { read() }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            trimmed.isEmpty ? delete() : write(trimmed)
        }
    }

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read() -> String? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    private static func write(_ value: String) {
        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery() as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery()
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
