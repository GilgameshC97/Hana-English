import Foundation
#if canImport(Security)
import Security
#endif

/// Minimal secret storage contract. The app uses `KeychainStore`; tests use
/// `InMemorySecretStore`.
nonisolated protocol HanaSecretStore: Sendable {
    func data(for account: String) throws -> Data?
    func set(_ data: Data, for account: String) throws
    func remove(_ account: String) throws
}

nonisolated extension HanaSecretStore {
    func string(for account: String) throws -> String? {
        guard let data = try data(for: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setString(_ value: String?, for account: String) throws {
        guard let value, !value.isEmpty else {
            try remove(account)
            return
        }
        try set(Data(value.utf8), for: account)
    }
}

nonisolated enum HanaSecretStoreError: Error, Equatable, Sendable {
    case unexpectedStatus(Int32)
    case invalidResult
    case unavailable
}

/// Thread-safe in-memory store for tests and previews.
nonisolated final class InMemorySecretStore: HanaSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data]

    init(_ values: [String: Data] = [:]) {
        self.values = values
    }

    func data(for account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[account]
    }

    func set(_ data: Data, for account: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[account] = data
    }

    func remove(_ account: String) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: account)
    }

    var allAccounts: [String] {
        lock.lock(); defer { lock.unlock() }
        return values.keys.sorted()
    }
}

#if canImport(Security)
/// Generic-password Keychain wrapper with a fixed service, data-protection
/// keychain and `AfterFirstUnlockThisDeviceOnly` accessibility (secrets are
/// never synced to iCloud Keychain or restored to another device).
///
/// Earlier builds wrote items through `HanaKeychain` **without** a service
/// attribute. When `migratesLegacyItems` is true, a read miss falls back to
/// such legacy items, re-saves them under this service and deletes the
/// legacy copy.
nonisolated struct KeychainStore: HanaSecretStore {
    static let hanaService = "sh.celia.hana.secrets"
    static let hana = KeychainStore(service: hanaService, migratesLegacyItems: true)

    let service: String
    let migratesLegacyItems: Bool

    init(service: String, migratesLegacyItems: Bool = false) {
        self.service = service
        self.migratesLegacyItems = migratesLegacyItems
    }

    func data(for account: String) throws -> Data? {
        var query = baseQuery(for: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return migratesLegacyItems ? try migrateLegacyItem(account: account) : nil
        }
        guard status == errSecSuccess else { throw HanaSecretStoreError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw HanaSecretStoreError.invalidResult }
        return data
    }

    func set(_ data: Data, for account: String) throws {
        var attributes = baseQuery(for: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updates: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(baseQuery(for: account) as CFDictionary, updates as CFDictionary)
            guard updateStatus == errSecSuccess else { throw HanaSecretStoreError.unexpectedStatus(updateStatus) }
            return
        }
        guard status == errSecSuccess else { throw HanaSecretStoreError.unexpectedStatus(status) }
    }

    func remove(_ account: String) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw HanaSecretStoreError.unexpectedStatus(status)
        }
        if migratesLegacyItems {
            removeLegacyItems(account: account)
        }
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// Items created by the old `HanaKeychain` helper: same account, no service.
    private func legacyItems(account: String) -> [[String: Any]] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.filter { (($0[kSecAttrService as String] as? String) ?? "").isEmpty }
    }

    private func migrateLegacyItem(account: String) throws -> Data? {
        guard let legacy = legacyItems(account: account).first,
              let data = legacy[kSecValueData as String] as? Data else { return nil }
        try set(data, for: account)
        removeLegacyItems(account: account)
        return data
    }

    private func removeLegacyItems(account: String) {
        guard !legacyItems(account: account).isEmpty else { return }
        // Only delete the service-less copy. We never delete "by account"
        // alone, because HanaSessionCookieStore keeps items with the same
        // account names under its own service. If this fails the stale legacy
        // item is harmless: reads always prefer the service-scoped copy.
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "",
        ] as CFDictionary)
    }
}
#endif
