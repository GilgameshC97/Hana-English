import Foundation

/// One-shot migration that moves secrets which older builds (or the
/// pre-refactor binary) kept in `UserDefaults` into the secret store, then
/// deletes the plaintext copies. Safe to run on every launch: it is a no-op
/// once nothing is left to move.
///
/// Site cookie headers (`Hana.SiteWebSession.*cookieHeader`) are *not* handled
/// here; `HanaSessionCookieStore` already migrates those lazily into its own
/// Keychain service.
nonisolated enum HanaSecretsMigration {
    static let completedKey = "hana.secrets.migratedToKeychain.v1"

    /// UserDefaults key → Keychain account.
    static let keyMap: [(defaultsKey: String, account: String)] = [
        ("hana.hh.clientID", "hana.hh.clientID"),
        ("hana.hh.host", "hana.hh.host"),
        ("hana.hh.port", "hana.hh.port"),
        ("hana.hh.ehUsername", "hana.hh.ehUsername"),
        ("hana.hh.exCookies", "hana.hh.exCookies"),
        ("hana.lockSettingsPin", "hana.lockSettingsPin"),
        ("hana.lockSettingsPIN", "hana.lockSettingsPin"),
        ("hana.settings.lockSettingsPIN", "hana.lockSettingsPin"),
    ]

    struct Result: Equatable, Sendable {
        var moved: [String] = []
        var failed: [String] = []
    }

    @discardableResult
    static func run(defaults: UserDefaults, store: any HanaSecretStore) -> Result {
        var result = Result()
        for (defaultsKey, account) in keyMap {
            guard let value = plaintextValue(defaults, key: defaultsKey) else { continue }
            do {
                // Never overwrite a newer Keychain value with a stale plaintext one.
                if try store.data(for: account) == nil {
                    try store.setString(value, for: account)
                }
                defaults.removeObject(forKey: defaultsKey)
                result.moved.append(defaultsKey)
            } catch {
                result.failed.append(defaultsKey)
            }
        }
        if result.failed.isEmpty {
            defaults.set(true, forKey: completedKey)
        }
        return result
    }

    private static func plaintextValue(_ defaults: UserDefaults, key: String) -> String? {
        if let string = defaults.string(forKey: key), !string.isEmpty { return string }
        if let data = defaults.data(forKey: key), let string = String(data: data, encoding: .utf8), !string.isEmpty {
            return string
        }
        if let number = defaults.object(forKey: key) as? NSNumber { return number.stringValue }
        return nil
    }
}
