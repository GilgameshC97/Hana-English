import Foundation
import Observation
import SwiftUI
import Security

#if os(iOS)
import UIKit
#endif

enum HanaSourceType: String, Codable, CaseIterable, Identifiable {
    case hanime = "Hanime-style Scraper"
    case generic = "Generic Video Site"
    case apiFeed = "API / RSS Feed"
    case hantaiAtHome = "H@H / E-Hentai / ExHentai"
    case jellyfin = "Jellyfin Server"

    var id: String { rawValue }

    var providerKind: ProviderKind {
        switch self {
        case .hanime: .hanime
        case .generic: .genericLink
        case .apiFeed: .feedLink
        case .hantaiAtHome: .hentaiAtHomeLink
        case .jellyfin: .jellyfin
        }
    }

    init(providerKind: ProviderKind) {
        switch providerKind {
        case .hanime: self = .hanime
        case .genericLink: self = .generic
        case .feedLink: self = .apiFeed
        case .hentaiAtHomeLink: self = .hantaiAtHome
        case .jellyfin: self = .jellyfin
        }
    }

    /// Sources that play inside Hana rather than only producing links.
    var isPlayable: Bool { providerKind.isPlayable }
}

/// UI editing model for one source. Persistence now goes through
/// `ProviderRegistry` (`hana.providers.v1`); this struct maps 1:1 onto
/// `ProviderSourceConfiguration`.
struct HanaSource: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var baseURL: String
    var type: HanaSourceType
    var enabled: Bool
    var searchEndpoint: String
    var browseEndpoint: String
    var lastTestAt: Date?
    var isConnected: Bool?
    var profileID: UUID?
    var authMethod: ProviderAuthMethod = .none
    var username: String?

    init(id: UUID, name: String, baseURL: String, type: HanaSourceType, enabled: Bool,
         searchEndpoint: String, browseEndpoint: String, lastTestAt: Date?, isConnected: Bool?, profileID: UUID? = nil,
         authMethod: ProviderAuthMethod = .none, username: String? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.type = type
        self.enabled = enabled
        self.searchEndpoint = searchEndpoint
        self.browseEndpoint = browseEndpoint
        self.lastTestAt = lastTestAt
        self.isConnected = isConnected
        self.profileID = profileID
        self.authMethod = authMethod
        self.username = username
    }

    init(configuration: ProviderSourceConfiguration) {
        self.init(
            id: configuration.id,
            name: configuration.name,
            baseURL: configuration.baseURL,
            type: HanaSourceType(providerKind: configuration.kind),
            enabled: configuration.enabled,
            searchEndpoint: configuration.searchEndpoint,
            browseEndpoint: configuration.browseEndpoint,
            lastTestAt: configuration.lastTestAt,
            isConnected: configuration.isConnected,
            profileID: configuration.profileID,
            authMethod: configuration.authMethod,
            username: configuration.username
        )
    }

    func configuration(updating existing: ProviderSourceConfiguration?) -> ProviderSourceConfiguration {
        var configuration = existing ?? ProviderSourceConfiguration(name: name, kind: type.providerKind, baseURL: baseURL)
        configuration.id = id
        configuration.name = name
        configuration.kind = type.providerKind
        configuration.baseURL = baseURL
        configuration.enabled = enabled
        configuration.searchEndpoint = searchEndpoint
        configuration.browseEndpoint = browseEndpoint
        configuration.lastTestAt = lastTestAt
        configuration.isConnected = isConnected
        configuration.profileID = profileID
        configuration.authMethod = type == .jellyfin ? authMethod : .none
        configuration.username = type == .jellyfin ? username?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil
        if existing?.baseURL != baseURL || existing?.username != configuration.username || existing?.kind != configuration.kind {
            configuration.remoteUserID = nil
        }
        return configuration
    }

    static func newDraft() -> HanaSource {
        HanaSource(id: UUID(), name: "", baseURL: "", type: .hanime, enabled: true,
                   searchEndpoint: "/search", browseEndpoint: "/", lastTestAt: nil, isConnected: nil)
    }
}

struct HanaSourceSearchResult: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let sourceName: String
    let sourceID: UUID
    let detailURL: URL?
    let profileName: String?
    /// Set for results from playable providers (e.g. Jellyfin); navigates to
    /// `HanaRoute.providerItem` instead of opening a link.
    let itemRef: MediaItemRef?
    let coverURL: URL?
    let subtitle: String?

    init(title: String, sourceName: String, sourceID: UUID, detailURL: URL?, profileName: String? = nil,
         itemRef: MediaItemRef? = nil, coverURL: URL? = nil, subtitle: String? = nil) {
        self.title = title
        self.sourceName = sourceName
        self.sourceID = sourceID
        self.detailURL = detailURL
        self.profileName = profileName
        self.itemRef = itemRef
        self.coverURL = coverURL
        self.subtitle = subtitle
    }
}

/// Facade kept for the existing Settings/Search UI. Storage and provider
/// construction now live in `ProviderRegistry`; link-only legacy source types
/// still use `HanaSourceSearchAdapter`.
@Observable
final class HanaSourceManager {
    static let storageKey = ProviderRegistry.storageKey
    static let legacyStorageKey = ProviderRegistry.legacyStorageKey

    @ObservationIgnored let registry: ProviderRegistry

    var sources: [HanaSource] {
        registry.configurations.map(HanaSource.init(configuration:))
    }

    init(registry: ProviderRegistry = HanaProviderEnvironment.registry) {
        self.registry = registry
    }

    func add(_ source: HanaSource) {
        registry.add(source.configuration(updating: nil))
    }

    func update(_ source: HanaSource) {
        registry.update(source.configuration(updating: registry.configuration(id: source.id)))
    }

    func delete(at offsets: IndexSet) {
        // Never delete the built-in Hanime source; its ID keys watch history.
        let deletable = IndexSet(offsets.filter { registry.configurations[$0].providerID != .builtInHanime })
        registry.remove(atOffsets: deletable)
    }

    func move(from source: IndexSet, to destination: Int) {
        registry.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: Secrets (Keychain only)

    func setSecret(_ value: String?, _ kind: ProviderSourceConfiguration.SecretKind, for sourceID: UUID) {
        try? registry.secrets.setString(value, for: ProviderSourceConfiguration.secretAccount(sourceID, kind))
        if kind != .accessToken {
            // Credentials changed: force a fresh sign-in.
            try? registry.secrets.remove(ProviderSourceConfiguration.secretAccount(sourceID, .accessToken))
        }
    }

    func hasSecret(_ kind: ProviderSourceConfiguration.SecretKind, for sourceID: UUID) -> Bool {
        ((try? registry.secrets.string(for: ProviderSourceConfiguration.secretAccount(sourceID, kind))) ?? nil)?.isEmpty == false
    }

    // MARK: Connection test

    func testConnection(_ source: HanaSource) async -> (Bool, String) {
        if source.type == .jellyfin {
            if registry.configuration(id: source.id) == nil { add(source) } else { update(source) }
            let result = await registry.testConnection(id: source.id)
            return (result.success, result.message)
        }
        guard let base = URL(string: source.baseURL),
              let scheme = base.scheme, ["http", "https"].contains(scheme),
              let host = base.host, !host.isEmpty else {
            return (false, "Invalid URL")
        }
        var request = URLRequest(url: base)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 12
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let success = (200..<400).contains(status)
            registry.recordConnectionTest(id: source.id, success: success)
            return (success, success ? "Connected (HTTP \(status))" : "Connection failed (HTTP \(status))")
        } catch {
            registry.recordConnectionTest(id: source.id, success: false)
            return (false, "Connection failed: \(error.localizedDescription)")
        }
    }

    // MARK: Search

    /// Searches enabled sources other than the built-in site (which the main
    /// search already covers). Playable providers return navigable results;
    /// legacy link-only types keep their old behaviour. Everything passes the
    /// content policy.
    func globalSearch(query: String) async -> [HanaSourceSearchResult] {
        guard !ContentSafetyPolicy.isBlocked(query) else { return [] }
        let configurations = registry.configurations.filter(\.enabled)
        let linkSources = configurations
            .filter { !$0.kind.isPlayable }
            .map(HanaSource.init(configuration:))

        async let providerResults = registry.unifiedSearch(SearchQuery(text: query), excluding: [.hanime])
        var linkResults: [HanaSourceSearchResult] = []
        await withTaskGroup(of: [HanaSourceSearchResult].self) { group in
            for source in linkSources {
                group.addTask {
                    await HanaSourceSearchAdapter.search(query: query, source: source)
                }
            }
            for await sourceResults in group { linkResults.append(contentsOf: sourceResults) }
        }

        let playable = await providerResults.results.map { result in
            HanaSourceSearchResult(
                title: result.item.title,
                sourceName: result.sourceName,
                sourceID: result.item.ref.providerID.sourceID,
                detailURL: nil,
                itemRef: result.item.ref,
                coverURL: result.item.coverURL,
                subtitle: result.item.subtitle
            )
        }

        var seen = Set<String>()
        let links = linkResults.filter { result in
            guard !ContentSafetyPolicy.isBlocked(result.title) else { return false }
            let key = result.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return seen.insert(key).inserted
        }
        return playable + links
    }

    static func profileName(for profileID: UUID?) -> String? {
        guard let profileID,
              let data = UserDefaults.standard.data(forKey: HanaSiteProfileManager.storageKey),
              let profiles = try? JSONDecoder().decode([SiteProfile].self, from: data) else { return nil }
        return profiles.first(where: { $0.id == profileID })?.displayName
    }

    func resolveLookup(_ text: String) async -> HanaSourceSearchResult? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let url = URL(string: value)
        for source in sources where source.enabled {
            if let url, url.absoluteString.contains(source.baseURL.replacingOccurrences(of: "/", with: "")) {
                return HanaSourceSearchResult(title: url.lastPathComponent, sourceName: source.name, sourceID: source.id, detailURL: url, profileName: Self.profileName(for: source.profileID))
            }
            if let sourceURL = URL(string: source.baseURL),
               let detail = URL(string: "\(sourceURL.absoluteString)\(value)") {
                return HanaSourceSearchResult(title: value, sourceName: source.name, sourceID: source.id, detailURL: detail, profileName: Self.profileName(for: source.profileID))
            }
        }
        return nil
    }
}

struct HanaSourceSearchAdapter {
    static func search(query: String, source: HanaSource) async -> [HanaSourceSearchResult] {
        guard let base = URL(string: source.baseURL) else { return [] }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        let endpoint = source.type == .hantaiAtHome ? "https://e-hentai.org/" : base.absoluteString
        if source.type == .hantaiAtHome, var hentai = URLComponents(string: endpoint) {
            hentai.queryItems = [URLQueryItem(name: "f_search", value: query)]
            return await scrapeTitles(hentai.url, source: source)
        }
        if source.type == .apiFeed,
           var api = URLComponents(url: base.appendingPathComponent(source.searchEndpoint), resolvingAgainstBaseURL: false) {
            api.queryItems = [URLQueryItem(name: "q", value: query)]
            return await decodeFeed(api.url, source: source)
        }
        return await scrapeTitles(base.appendingPathComponent(source.searchEndpoint).appendingPathComponent(query), source: source)
    }

    private static func scrapeTitles(_ url: URL?, source: HanaSource) async -> [HanaSourceSearchResult] {
        guard let url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8) ?? ""
            let pattern = #"(?:<a[^>]+href=["']([^"']+)["'][^>]*>[^<]*<[^>]*>([^<]+)<|<title>([^<]+)</title>)"#
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            var output: [HanaSourceSearchResult] = []
            for match in matches.prefix(30) {
                let titleRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
                guard titleRange.location != NSNotFound, let range = Range(titleRange, in: html) else { continue }
                let title = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                var detail: URL?
                if match.range(at: 1).location != NSNotFound, let hrefRange = Range(match.range(at: 1), in: html) {
                    detail = URL(string: String(html[hrefRange]), relativeTo: url)?.absoluteURL
                }
                output.append(HanaSourceSearchResult(title: title, sourceName: source.name, sourceID: source.id, detailURL: detail, profileName: HanaSourceManager.profileName(for: source.profileID)))
            }
            return output
        } catch { return [] }
    }

    private static func decodeFeed(_ url: URL?, source: HanaSource) async -> [HanaSourceSearchResult] {
        guard let url else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            return (json ?? []).compactMap { item in
                guard let title = item["title"] as? String else { return nil }
                let detail = (item["url"] as? String).flatMap(URL.init(string:))
                return HanaSourceSearchResult(title: title, sourceName: source.name, sourceID: source.id, detailURL: detail, profileName: HanaSourceManager.profileName(for: source.profileID))
            }
        } catch { return [] }
    }
}

/// Thin compatibility wrapper used across the app. Backed by
/// `KeychainStore.hana` (service `sh.celia.hana.secrets`,
/// AfterFirstUnlockThisDeviceOnly, data-protection keychain). Items written by
/// earlier builds without a service are migrated on first read.
enum HanaKeychain {
    static func save(_ value: String, account: String) {
        saveData(Data(value.utf8), account: account)
    }

    static func read(account: String) -> String? {
        readData(account: account).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func delete(account: String) {
        try? KeychainStore.hana.remove(account)
    }
}
