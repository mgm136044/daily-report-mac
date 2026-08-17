import Foundation
import Security

public enum TokenAccount {
    public static let notion = "notion-token"
}

public protocol TokenStore {
    func read(_ account: String) throws -> String?
    func write(_ secret: String, account: String) throws
    func delete(_ account: String) throws
}

public final class InMemoryTokenStore: TokenStore {
    private var items: [String: String] = [:]
    public init() {}
    public func read(_ account: String) throws -> String? { items[account] }
    public func write(_ secret: String, account: String) throws { items[account] = secret }
    public func delete(_ account: String) throws { items[account] = nil }
}

public enum KeychainError: Error, Equatable { case unexpectedStatus(OSStatus) }

/// A generic-password item scoped to this app's service. It is our own item,
/// not shared with any Apple tool, so SecItem is safe here (no partition-list
/// re-stamping like the shared Claude Code credentials suffer from).
public final class KeychainTokenStore: TokenStore {
    private let service: String
    public init(service: String = "com.mgm136044.DailyReportMac") { self.service = service }

    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read(_ account: String) throws -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, update)
        if status == errSecSuccess { return }
        if status == errSecItemNotFound {
            var add = baseQuery(account)
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }
        throw KeychainError.unexpectedStatus(status)
    }

    public func delete(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
