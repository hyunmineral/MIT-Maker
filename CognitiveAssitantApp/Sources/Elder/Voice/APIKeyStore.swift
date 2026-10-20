import Foundation
import Security

/// Keeps the OpenAI API key in the Keychain. Never put it in source or `Info.plist`.
///
/// ⚠️ **A key embedded in a client app can in principle be extracted.**
/// That's acceptable during the pilot, where staff manage the device, but
/// **for real deployment the key must live on a server, with the app calling that server.**
/// An item to add to section 8 (open issues) of the hardware spec.
enum APIKeyStore {

    private static let service = "com.tictechtoe.RobotForElders"
    private static let account = "openai.api.key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        clear()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Accessible once unlocked after a reboot. The kiosk restarts unattended.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var hasKey: Bool { load() != nil }

    /// Masked form used for display. The full key is never exposed again.
    static var maskedKey: String? {
        guard let key = load() else { return nil }
        let tail = String(key.suffix(4))
        return "sk-…\(tail)"
    }
}
