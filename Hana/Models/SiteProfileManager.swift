import Foundation
import Observation
import Security
import SwiftUI

enum HanaLoginType: String, Codable, Identifiable, CaseIterable {
    case cookieSync = "Cookie Sync"
    case account = "Account Login"
    case token = "Token"

    var id: String { rawValue }
}

enum HanaLoginState: String, Codable, Equatable {
    case loggedOut = "Logged Out"
    case loggedIn = "Logged In"
    case syncing = "Syncing"
    case error = "Error"
}

struct SiteProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var baseURL: String
    var loginType: HanaLoginType
    var sourceID: UUID?
    var enabled: Bool
    var loginState: HanaLoginState
    var lastCookieSyncAt: Date?
    var error: String?
}

@Observable
final class HanaSiteProfileManager {
    static let storageKey = "hana.siteProfiles.v1"
    static let activeProfileIDKey = "hana.siteProfiles.activeID"

    private(set) var profiles: [SiteProfile]
    private let defaults: UserDefaults

    var activeProfile: SiteProfile? {
        guard let id = activeProfileID else { return nil }
        return profiles.first(where: { $0.id == id && $0.enabled })
            ?? profiles.first(where: { $0.enabled })
    }

    private(set) var activeProfileID: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
        let defaultProfile = SiteProfile(
            id: defaultID,
            displayName: "hanime1.me",
            baseURL: HanaSiteBaseURL.defaultValue,
            loginType: .cookieSync,
            sourceID: nil,
            enabled: true,
            loginState: .loggedOut,
            lastCookieSyncAt: nil,
            error: nil
        )

        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([SiteProfile].self, from: data),
           !saved.isEmpty {
            profiles = saved
        } else {
            profiles = [defaultProfile]
            if let data = try? JSONEncoder().encode(profiles) {
                defaults.set(data, forKey: Self.storageKey)
            }
        }

        if let raw = defaults.string(forKey: Self.activeProfileIDKey),
           let id = UUID(uuidString: raw),
           profiles.contains(where: { $0.id == id && $0.enabled }) {
            activeProfileID = id
        } else {
            activeProfileID = profiles.first(where: { $0.enabled })?.id
            defaults.set(activeProfileID?.uuidString, forKey: Self.activeProfileIDKey)
        }

        if let baseURL = defaults.string(forKey: HanaSettingsKey.siteBaseURL),
           let normalized = HanaSiteBaseURL.normalized(baseURL) {
            if activeProfileID == defaultID,
               !profiles.isEmpty,
               profiles[0].id == defaultID {
                profiles[0].baseURL = normalized
                save()
            }
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func add(_ profile: SiteProfile) {
        profiles.append(profile)
        save()
    }

    func update(_ profile: SiteProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        save()
    }

    func delete(_ profile: SiteProfile) {
        profiles.removeAll(where: { $0.id == profile.id })
        clearSecrets(for: profile)
        if activeProfileID == profile.id {
            activeProfileID = profiles.first(where: { $0.enabled })?.id
            if let activeProfileID {
                defaults.set(activeProfileID.uuidString, forKey: Self.activeProfileIDKey)
            } else {
                defaults.removeObject(forKey: Self.activeProfileIDKey)
            }
        }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        profiles.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func activate(_ profile: SiteProfile) {
        guard profile.enabled, let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        activeProfileID = profiles[index].id
        defaults.set(profile.id.uuidString, forKey: Self.activeProfileIDKey)
        defaults.set(profile.baseURL, forKey: HanaSettingsKey.siteBaseURL)
    }

    func setLoginMetadata(_ profileID: UUID, state: HanaLoginState, lastSync: Date? = nil, error: String? = nil) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].loginState = state
        if let lastSync { profiles[index].lastCookieSyncAt = lastSync }
        profiles[index].error = error
        save()
    }

    func saveAccountCredential(profileID: UUID, email: String, password: String) {
        let payload = Data("\(email)\u{0}\(password)".utf8)
        HanaKeychain.saveData(payload, account: credentialAccount(profileID))
    }

    func readAccountCredential(profileID: UUID) -> (email: String, password: String)? {
        guard let data = HanaKeychain.readData(account: credentialAccount(profileID)),
              let value = String(data: data, encoding: .utf8) else { return nil }
        let parts = value.components(separatedBy: "\u{0}")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    func clearSecrets(for profile: SiteProfile) {
        HanaKeychain.delete(account: credentialAccount(profile.id))
        HanaKeychain.delete(account: cookieAccount(profile.id))
        HanaKeychain.delete(account: tokenAccount(profile.id))
        if let baseURL = URL(string: profile.baseURL) {
            HanaSessionCookieStore().removeCookieHeader(for: baseURL, profileID: profile.id)
        }
        let suffix = HanaSessionCookieStore.profileKeySuffix(profile.id)
        let keys = [
            "Hana.SiteWebSession.\(suffix).isLoggedIn",
            "Hana.SiteWebSession.\(suffix).userID",
            "Hana.SiteWebSession.\(suffix).username",
            "Hana.SiteWebSession.\(suffix).avatarURLString",
            "Hana.SiteWebSession.\(suffix).cloudflareVerifiedAt"
        ]
        for key in keys { defaults.removeObject(forKey: key) }
    }

    func credentialAccount(_ profileID: UUID) -> String { "hana.profile.\(profileID.uuidString).credentials" }
    func cookieAccount(_ profileID: UUID) -> String { "hana.profile.\(profileID.uuidString).cookies" }
    func tokenAccount(_ profileID: UUID) -> String { "hana.profile.\(profileID.uuidString).token" }
}

extension HanaKeychain {
    static func saveData(_ data: Data, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account,
                                    kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func readData(account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
}
