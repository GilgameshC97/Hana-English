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

    var id: String { rawValue }
}

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

    init(id: UUID, name: String, baseURL: String, type: HanaSourceType, enabled: Bool,
         searchEndpoint: String, browseEndpoint: String, lastTestAt: Date?, isConnected: Bool?, profileID: UUID? = nil) {
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
    }
}

struct HanaSourceSearchResult: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let sourceName: String
    let sourceID: UUID
    let detailURL: URL?
    let profileName: String?

    init(title: String, sourceName: String, sourceID: UUID, detailURL: URL?, profileName: String? = nil) {
        self.title = title
        self.sourceName = sourceName
        self.sourceID = sourceID
        self.detailURL = detailURL
        self.profileName = profileName
    }
}

@Observable
final class HanaSourceManager {
    static let storageKey = "hana.sources.v1"
    private(set) var sources: [HanaSource]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([HanaSource].self, from: data) {
            sources = saved
        } else {
            sources = [HanaSource(
                id: UUID(), name: "Hanime1", baseURL: HanaSiteBaseURL.defaultValue,
                type: .hanime, enabled: true, searchEndpoint: "/search", browseEndpoint: "/",
                lastTestAt: nil, isConnected: nil
            )]
            save(defaults: defaults)
        }
    }

    private let defaults: UserDefaults

    func save() { save(defaults: defaults) }
    private func save(defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(sources) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func add(_ source: HanaSource) {
        sources.append(source)
        save()
    }

    func update(_ source: HanaSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = source
        save()
    }

    func delete(at offsets: IndexSet) {
        sources.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        sources.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func testConnection(_ source: HanaSource) async -> (Bool, String) {
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
            if var updated = sources.first(where: { $0.id == source.id }) {
                updated.lastTestAt = .now
                updated.isConnected = success
                update(updated)
            }
            return (success, success ? "Connected (HTTP \(status))" : "Connection failed (HTTP \(status))")
        } catch {
            if var updated = sources.first(where: { $0.id == source.id }) {
                updated.lastTestAt = .now
                updated.isConnected = false
                update(updated)
            }
            return (false, "Connection failed: \(error.localizedDescription)")
        }
    }

    func globalSearch(query: String) async -> [HanaSourceSearchResult] {
        let enabled = sources.filter(\.enabled)
        var results: [HanaSourceSearchResult] = []
        await withTaskGroup(of: [HanaSourceSearchResult].self) { group in
            for source in enabled {
                group.addTask {
                    await HanaSourceSearchAdapter.search(query: query, source: source)
                }
            }
            for await sourceResults in group { results.append(contentsOf: sourceResults) }
        }
        var seen = Set<String>()
        return results.filter { result in
            let key = result.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return seen.insert(key).inserted
        }
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

enum HanaKeychain {
    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account,
                                    kSecValueData as String: data]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
