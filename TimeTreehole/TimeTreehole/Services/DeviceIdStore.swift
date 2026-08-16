import Foundation

// MARK: - 设备标识持久化（Keychain）

/// 将匿名账号的设备标识 device_id 持久化到 Keychain。
/// Keychain 在 App 卸载重装后仍会保留（除非用户抹掉设备或关闭 iCloud 钥匙串），
/// 因此比 UserDefaults 更适合做"同一设备复用同一匿名账号"的稳定标识。
enum DeviceIdStore {
    private static let service = "com.timetreehole.device"
    private static let account = "deviceId"

    /// 读取已保存的 device_id，不存在返回 nil
    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let str = String(data: data, encoding: .utf8), !str.isEmpty else {
            return nil
        }
        return str
    }

    /// 保存 device_id 到 Keychain
    @discardableResult
    static func save(_ value: String) -> Bool {
        // 先尝试删除旧值，避免重复条目导致写入失败
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let data = Data(value.utf8)
        let addQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String:   data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }
}
