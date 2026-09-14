import Foundation
import Security
public enum KeychainStore {
    private static let base: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"com.guochengqian.cloudwatch", kSecAttrAccount as String:"desktop-eapi"]
    public static func save(_ config: AccountConfiguration) throws {
        let data = try JSONEncoder().encode(config)
        let update = SecItemUpdate(base as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if update == errSecItemNotFound {
            var query = base; query[kSecValueData as String] = data; query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw MusicError.message("无法安全保存登录信息。") }
        } else if update != errSecSuccess { throw MusicError.message("无法更新登录信息（\(update)）。") }
    }
    public static func load() -> AccountConfiguration? {
        var query = base; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AccountConfiguration.self, from:data)
    }
    public static func delete() { SecItemDelete(base as CFDictionary) }
}
