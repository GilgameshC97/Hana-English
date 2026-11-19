import Foundation
import Testing
@testable import HanaProviderCore

/// Fake provider returning fixed data, including blocked items.
nonisolated struct FakeProvider: VideoProvider {
    let id: ProviderID
    let displayName = "Fake"
    let capabilities: ProviderCapabilities = [.search, .details, .streams]
    let items: [MediaItemSummary]
    var extraDetailTags: [String] = ["Drama"]

    func search(_ query: SearchQuery) async throws -> SearchPage {
        SearchPage(items: items, page: query.page, hasMore: false, totalCount: items.count)
    }

    func details(for ref: MediaItemRef) async throws -> MediaItemDetail {
        let summary = items.first { $0.ref == ref } ?? items[0]
        return MediaItemDetail(summary: summary, alternateTitle: nil, overview: nil, releaseDate: nil,
                               tags: summary.tags + extraDetailTags, studios: [], seriesTitle: nil, seriesRef: nil,
                               related: items, isFavorite: false, externalURL: nil)
    }

    func streams(for ref: MediaItemRef) async throws -> [StreamSource] {
        [StreamSource(url: URL(string: "https://example.com/v.mp4")!, kind: .progressive, quality: "1080p")]
    }

    func testConnection() async -> (success: Bool, message: String) { (true, "ok") }
}

@MainActor
@Suite("Provider registry, migrations and keys")
struct RegistryAndMigrationTests {
    @Test("migrates hana.sources.v1 into hana.providers.v1")
    func legacyMigration() throws {
        let defaults = makeDefaults()
        defaults.set(try Fixture.data("legacy-sources-v1"), forKey: "hana.sources.v1")

        let registry = ProviderRegistry(defaults: defaults, secrets: InMemorySecretStore()) { _, _ in nil }
        let kinds = registry.configurations.map(\.kind)
        #expect(kinds == [.hanime, .genericLink, .feedLink, .genericLink])
        #expect(registry.configurations[0].providerID == .builtInHanime)
        #expect(registry.configurations[2].profileID == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        #expect(registry.configurations[2].searchEndpoint == "/api/search")
        #expect(defaults.data(forKey: ProviderRegistry.storageKey) != nil)
        #expect(defaults.data(forKey: "hana.sources.v1") != nil) // kept for downgrade

        // A second launch reads the new key, not the legacy one.
        defaults.set(Data("[]".utf8), forKey: "hana.sources.v1")
        let relaunched = ProviderRegistry(defaults: defaults, secrets: InMemorySecretStore()) { _, _ in nil }
        #expect(relaunched.configurations.count == 4)
    }

    @Test("fresh install gets the built-in Hanime source")
    func freshInstall() {
        let registry = ProviderRegistry(defaults: makeDefaults(), secrets: InMemorySecretStore()) { _, _ in nil }
        #expect(registry.configurations.map(\.kind) == [.hanime])
        #expect(registry.configurations[0].providerID == .builtInHanime)
    }

    @Test("unified search and details enforce the blocklist")
    func registryEnforcesPolicy() async throws {
        let sourceID = UUID()
        let providerID = ProviderID(kind: .jellyfin, sourceID: sourceID)
        let allowed = MediaItemSummary(ref: MediaItemRef(providerID: providerID, itemID: "1"), title: "Nature", tags: ["OL"])
        let blocked = MediaItemSummary(ref: MediaItemRef(providerID: providerID, itemID: "2"), title: "Example", tags: ["正太"])
        let fake = FakeProvider(id: providerID, items: [allowed, blocked])

        let registry = ProviderRegistry(defaults: makeDefaults(), secrets: InMemorySecretStore()) { configuration, _ in
            configuration.kind == .jellyfin ? fake : nil
        }
        registry.add(ProviderSourceConfiguration(id: sourceID, name: "Home", kind: .jellyfin, baseURL: "https://x.example"))

        let (results, failures) = await registry.unifiedSearch(SearchQuery(text: "n"), excluding: [.hanime])
        #expect(failures.isEmpty)
        #expect(results.map(\.item.ref.itemID) == ["1"])

        let detail = try await registry.details(for: allowed.ref)
        #expect(detail.tags == ["OL", "Drama"])
        #expect(detail.related.map(\.ref.itemID) == ["1"])

        await #expect(throws: VideoProviderError.blockedByContentPolicy) {
            _ = try await registry.details(for: blocked.ref)
        }
        await #expect(throws: VideoProviderError.blockedByContentPolicy) {
            _ = try await registry.streams(for: blocked.ref)
        }
        let blockedQuery = await registry.unifiedSearch(SearchQuery(text: "shota"))
        #expect(blockedQuery.results.isEmpty)
    }

    @Test("an item whose detail tags are blocked is refused entirely")
    func detailTagBlocksItem() async throws {
        let sourceID = UUID()
        let providerID = ProviderID(kind: .jellyfin, sourceID: sourceID)
        let item = MediaItemSummary(ref: MediaItemRef(providerID: providerID, itemID: "1"), title: "Nature", tags: [])
        let fake = FakeProvider(id: providerID, items: [item], extraDetailTags: ["JK"])
        let registry = ProviderRegistry(defaults: makeDefaults(), secrets: InMemorySecretStore()) { _, _ in fake }
        registry.add(ProviderSourceConfiguration(id: sourceID, name: "Home", kind: .jellyfin, baseURL: "https://x.example"))
        await #expect(throws: VideoProviderError.blockedByContentPolicy) {
            _ = try await registry.details(for: item.ref)
        }
    }

    @Test("removing a source clears its Keychain secrets")
    func removeClearsSecrets() throws {
        let secrets = InMemorySecretStore()
        let registry = ProviderRegistry(defaults: makeDefaults(), secrets: secrets) { _, _ in nil }
        let configuration = ProviderSourceConfiguration(name: "Home", kind: .jellyfin, baseURL: "https://x.example", authMethod: .apiKey)
        registry.add(configuration)
        try secrets.setString("k", for: configuration.secretAccount(.apiKey))
        registry.remove(atOffsets: IndexSet(integer: 1))
        #expect(try secrets.string(for: configuration.secretAccount(.apiKey)) == nil)
    }

    @Test("MediaItemRef storage keys round-trip; legacy video codes stay bare")
    func storageKeys() {
        let legacy = MediaItemRef.legacyHanime(videoCode: "12444")
        #expect(legacy.storageKey == "12444")
        #expect(MediaItemRef(storageKey: "12444") == legacy)

        let ref = MediaItemRef(providerID: ProviderID(kind: .jellyfin, sourceID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!), itemID: "abc:def")
        #expect(ref.storageKey == "jellyfin:11111111-2222-3333-4444-555555555555:abc:def")
        #expect(MediaItemRef(storageKey: ref.storageKey) == ref)
        #expect(MediaItemRef(storageKey: "") == nil)
    }

    @Test("plaintext secrets move from UserDefaults to the secret store")
    func secretsMigration() throws {
        let defaults = makeDefaults()
        defaults.set("cookie=1", forKey: "hana.hh.exCookies")
        defaults.set("1234", forKey: "hana.lockSettingsPIN")
        defaults.set("unrelated", forKey: "hana.settings.themeColor")
        let store = InMemorySecretStore()
        try store.setString("5678", for: "hana.lockSettingsPin") // newer Keychain value wins

        let result = HanaSecretsMigration.run(defaults: defaults, store: store)

        #expect(Set(result.moved) == ["hana.hh.exCookies", "hana.lockSettingsPIN"])
        #expect(defaults.object(forKey: "hana.hh.exCookies") == nil)
        #expect(defaults.object(forKey: "hana.lockSettingsPIN") == nil)
        #expect(defaults.string(forKey: "hana.settings.themeColor") == "unrelated")
        #expect(try store.string(for: "hana.hh.exCookies") == "cookie=1")
        #expect(try store.string(for: "hana.lockSettingsPin") == "5678")
        #expect(defaults.bool(forKey: HanaSecretsMigration.completedKey))
    }
}

// Compile-time check of the pattern HanimeProvider uses in the app target:
// a MainActor-isolated class whose protocol witnesses are `nonisolated` and
// hop to the MainActor internally. If this stops compiling under the
// app-mirroring settings, HanimeProvider will too.
final class FakeMainActorRepository {
    var calls = 0
    func search(_ text: String) async throws -> [String] { calls += 1; return [text] }
}

final class MainActorPatternProvider: VideoProvider {
    nonisolated let id: ProviderID = .builtInHanime
    nonisolated let displayName = "Pattern"
    nonisolated let capabilities: ProviderCapabilities = [.search]
    private let repository = FakeMainActorRepository()

    nonisolated func search(_ query: SearchQuery) async throws -> SearchPage { try await mainSearch(query) }
    nonisolated func details(for ref: MediaItemRef) async throws -> MediaItemDetail { throw VideoProviderError.itemNotFound }
    nonisolated func streams(for ref: MediaItemRef) async throws -> [StreamSource] { [] }
    nonisolated func testConnection() async -> (success: Bool, message: String) { (true, "") }

    private func mainSearch(_ query: SearchQuery) async throws -> SearchPage {
        let titles = try await repository.search(query.text)
        return SearchPage(items: titles.map { MediaItemSummary(ref: .legacyHanime(videoCode: $0), title: $0) }, page: 1, hasMore: false, totalCount: nil)
    }
}

@Test("MainActor provider pattern works through the registry")
@MainActor
func mainActorPattern() async throws {
    let registry = ProviderRegistry(defaults: makeDefaults(), secrets: InMemorySecretStore()) { _, _ in nil }
    registry.builtInHanimeProvider = MainActorPatternProvider()
    let page = try await registry.search(SearchQuery(text: "123"), in: .builtInHanime)
    #expect(page.items.map(\.title) == ["123"])
}

@Test("server URLs keep http and proxy prefixes", arguments: [
    ("media.example.com", "https://media.example.com"),
    ("http://192.168.1.20:8096/", "http://192.168.1.20:8096"),
    ("https://example.com/jellyfin/", "https://example.com/jellyfin"),
])
func serverURLNormalization(input: String, expected: String) {
    #expect(ProviderServerURL.normalized(input) == expected)
}

@Test("invalid server URLs are rejected", arguments: ["", "ftp://x", "https://"])
func serverURLRejects(input: String) {
    #expect(ProviderServerURL.normalized(input) == nil)
}

@Test("clock durations parse")
func clockDurations() {
    #expect(MediaDuration.seconds(fromClock: "12:34") == 754)
    #expect(MediaDuration.seconds(fromClock: "1:02:03") == 3723)
    #expect(MediaDuration.seconds(fromClock: "abc") == nil)
}
