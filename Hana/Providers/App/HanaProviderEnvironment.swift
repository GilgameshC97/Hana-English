import Foundation
#if os(iOS)
import UIKit
#endif

/// App-side wiring for the provider layer: the shared registry, the factory
/// that turns a `ProviderSourceConfiguration` into a live provider, and the
/// Keychain-backed secret store.
enum HanaProviderEnvironment {
    static let deviceIDKey = "hana.provider.deviceID"

    /// Process-wide registry. `HanaSourceManager` instances (created as view
    /// `@State`) and `HanaServices` all share it so edits are visible
    /// everywhere immediately.
    static let registry: ProviderRegistry = {
        ProviderRegistry(
            defaults: .standard,
            secrets: KeychainStore.hana,
            defaultHanimeBaseURL: HanaSiteBaseURL.defaultValue,
            factory: makeProvider
        )
    }()

    static func makeProvider(_ configuration: ProviderSourceConfiguration, secrets: any HanaSecretStore) -> (any VideoProvider)? {
        switch configuration.kind {
        case .jellyfin:
            return try? JellyfinProvider(
                configuration: configuration,
                secrets: secrets,
                deviceID: deviceID(),
                deviceName: deviceName(),
                clientVersion: clientVersion()
            )
        case .hanime:
            // The built-in Hanime provider is registered by HanaServices. Extra
            // Hanime-style mirrors stay link-only until they get their own
            // HanaServices stack (see docs/VideoProviderRefactor.md).
            return nil
        case .genericLink, .feedLink, .hentaiAtHomeLink:
            return nil
        }
    }

    /// Stable, non-secret per-install identifier required by Jellyfin.
    static func deviceID(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: deviceIDKey), !existing.isEmpty { return existing }
        let created = UUID().uuidString
        defaults.set(created, forKey: deviceIDKey)
        return created
    }

    private static func deviceName() -> String {
#if os(iOS)
        UIDevice.current.model
#else
        "Mac"
#endif
    }

    private static func clientVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
