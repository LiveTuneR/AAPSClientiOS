import Security
import Foundation

enum KeychainKey: String, CaseIterable {
    case nsUrl
    case nsAccessToken
}

final class KeychainStore {
    private let service: String
    private let accessGroup: String?

    init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func set(_ value: String, for key: KeychainKey) throws {
        if let _ = try get(key) {
            try update(value, for: key)
        } else {
            try add(value, for: key)
        }
    }

    func get(_ key: KeychainKey) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        if status != errSecSuccess { throw KeychainError.unhandledStatus(status) }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return string
    }

    func delete(_ key: KeychainKey) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func add(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess { throw KeychainError.unhandledStatus(status) }
    }

    private func update(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        let query = baseQuery(for: key)
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status != errSecSuccess { throw KeychainError.unhandledStatus(status) }
    }

    private func baseQuery(for key: KeychainKey) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    /// Copy all keychain values from this store into `destination`, then delete
    /// them here. Idempotent: missing values are skipped. Used once at launch to
    /// move credentials from the app's default group into the shared access group
    /// so the widget extension can read them.
    func migrate(to destination: KeychainStore) throws {
        for key in KeychainKey.allCases {
            guard let value = try get(key) else { continue }
            try destination.set(value, for: key)
            if destination !== self {
                try delete(key)
            }
        }
    }
}

enum KeychainError: Error {
    case unhandledStatus(OSStatus)
    case unexpectedData
    case encodingFailed
}
