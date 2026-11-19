import Foundation

nonisolated enum ProviderAuthMethod: String, Codable, Sendable, CaseIterable, Hashable {
    case none
    case apiKey
    case password
}

/// Persisted configuration of one source. Non-secret fields only: API keys,
/// passwords and access tokens live in the Keychain under `secretAccount(_:)`.
nonisolated struct ProviderSourceConfiguration: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var kind: ProviderKind
    var baseURL: String
    var enabled: Bool
    var searchEndpoint: String
    var browseEndpoint: String
    var lastTestAt: Date?
    var isConnected: Bool?
    var profileID: UUID?
    var authMethod: ProviderAuthMethod
    /// Jellyfin user name (not secret) used for password sign-in, or to pick a
    /// user when authenticating with an API key.
    var username: String?
    /// Cached Jellyfin user ID resolved after sign-in (not secret).
    var remoteUserID: String?

    init(
        id: UUID = UUID(),
        name: String,
        kind: ProviderKind,
        baseURL: String,
        enabled: Bool = true,
        searchEndpoint: String = "/search",
        browseEndpoint: String = "/",
        lastTestAt: Date? = nil,
        isConnected: Bool? = nil,
        profileID: UUID? = nil,
        authMethod: ProviderAuthMethod = .none,
        username: String? = nil,
        remoteUserID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.enabled = enabled
        self.searchEndpoint = searchEndpoint
        self.browseEndpoint = browseEndpoint
        self.lastTestAt = lastTestAt
        self.isConnected = isConnected
        self.profileID = profileID
        self.authMethod = authMethod
        self.username = username
        self.remoteUserID = remoteUserID
    }

    var providerID: ProviderID {
        kind == .hanime && id == ProviderID.builtInHanime.sourceID
            ? .builtInHanime
            : ProviderID(kind: kind, sourceID: id)
    }

    enum SecretKind: String, Sendable {
        case apiKey
        case password
        case accessToken
    }

    static func secretAccount(_ sourceID: UUID, _ kind: SecretKind) -> String {
        "hana.provider.\(sourceID.uuidString).\(kind.rawValue)"
    }

    func secretAccount(_ kind: SecretKind) -> String {
        Self.secretAccount(id, kind)
    }
}

/// Reads the pre-refactor `hana.sources.v1` payload (array of `HanaSource`)
/// without depending on the app-side type.
nonisolated enum LegacySourcesMigration {
    static let legacyStorageKey = "hana.sources.v1"

    private struct LegacySource: Decodable {
        var id: UUID
        var name: String
        var baseURL: String
        var type: String
        var enabled: Bool
        var searchEndpoint: String?
        var browseEndpoint: String?
        var lastTestAt: Date?
        var isConnected: Bool?
        var profileID: UUID?
    }

    /// `HanaSourceType` raw values as they were stored on disk.
    static func kind(forLegacyType raw: String) -> ProviderKind {
        switch raw {
        case "Hanime-style Scraper": .hanime
        case "API / RSS Feed": .feedLink
        case "H@H / E-Hentai / ExHentai": .hentaiAtHomeLink
        case "Jellyfin Server": .jellyfin
        default: .genericLink
        }
    }

    static func decode(_ data: Data) -> [ProviderSourceConfiguration]? {
        guard let legacy = try? JSONDecoder().decode([LegacySource].self, from: data) else { return nil }
        var sawBuiltInHanime = false
        return legacy.map { source in
            var kind = kind(forLegacyType: source.type)
            var id = source.id
            // The first Hanime entry pointing at the configured site becomes the
            // built-in provider so history keyed by bare videoCode stays valid.
            if kind == .hanime, !sawBuiltInHanime {
                sawBuiltInHanime = true
                id = ProviderID.builtInHanime.sourceID
            } else if kind == .hanime {
                // Additional "Hanime-style" entries were link-only before; keep them so.
                kind = .genericLink
            }
            return ProviderSourceConfiguration(
                id: id,
                name: source.name,
                kind: kind,
                baseURL: source.baseURL,
                enabled: source.enabled,
                searchEndpoint: source.searchEndpoint ?? "/search",
                browseEndpoint: source.browseEndpoint ?? "/",
                lastTestAt: source.lastTestAt,
                isConnected: source.isConnected,
                profileID: source.profileID
            )
        }
    }
}

nonisolated enum ProviderServerURL {
    /// Normalizes a self-hosted server address. Unlike `HanaSiteBaseURL`, this
    /// keeps an explicit `http://` scheme (LAN servers; ATS allows local
    /// networking only) and keeps reverse-proxy path prefixes such as
    /// `/jellyfin`. Defaults to https when no scheme is given.
    static func normalized(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let withScheme = text.contains("://") ? text : "https://\(text)"
        guard var components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else { return nil }
        components.scheme = scheme
        while components.path.hasSuffix("/") { components.path.removeLast() }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }
}
