import Foundation
import Observation

/// One result row of a cross-provider search.
nonisolated struct ProviderSearchResult: Identifiable, Hashable, Sendable {
    var id: MediaItemRef { item.ref }
    let item: MediaItemSummary
    let sourceName: String
}

nonisolated struct ProviderSearchFailure: Hashable, Sendable {
    let sourceName: String
    let message: String
}

/// Owns the list of configured sources (replacing the link-only entries of
/// `HanaSourceManager`), builds `VideoProvider` instances for them, and is the
/// single choke point where `ContentSafetyPolicy` is applied to provider
/// output.
///
/// Storage: `hana.providers.v1` (JSON array of `ProviderSourceConfiguration`).
/// On first launch it migrates `hana.sources.v1`; the legacy key is left
/// untouched so an older build can still read it after a downgrade.
@MainActor
@Observable
final class ProviderRegistry {
    static let storageKey = "hana.providers.v1"
    static let legacyStorageKey = LegacySourcesMigration.legacyStorageKey

    typealias Factory = @MainActor (ProviderSourceConfiguration, any HanaSecretStore) -> (any VideoProvider)?

    private(set) var configurations: [ProviderSourceConfiguration]

    @ObservationIgnored let secrets: any HanaSecretStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let factory: Factory
    @ObservationIgnored private var providerCache: [UUID: (configuration: ProviderSourceConfiguration, provider: any VideoProvider)] = [:]

    /// The built-in Hanime provider is created by `HanaServices` (it needs the
    /// shared HTTP client / Cloudflare session) and registered here.
    @ObservationIgnored var builtInHanimeProvider: (any VideoProvider)?

    init(
        defaults: UserDefaults = .standard,
        secrets: any HanaSecretStore,
        defaultHanimeBaseURL: String = "https://hanime1.me",
        factory: @escaping Factory
    ) {
        self.defaults = defaults
        self.secrets = secrets
        self.factory = factory

        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([ProviderSourceConfiguration].self, from: data) {
            configurations = saved
        } else if let legacy = defaults.data(forKey: Self.legacyStorageKey),
                  let migrated = LegacySourcesMigration.decode(legacy) {
            configurations = migrated
            persist()
        } else {
            configurations = [ProviderSourceConfiguration(
                id: ProviderID.builtInHanime.sourceID,
                name: "Hanime1",
                kind: .hanime,
                baseURL: defaultHanimeBaseURL,
                searchEndpoint: "/search",
                browseEndpoint: "/"
            )]
            persist()
        }
    }

    // MARK: - Configuration CRUD

    func configuration(id: UUID) -> ProviderSourceConfiguration? {
        configurations.first { $0.id == id }
    }

    func add(_ configuration: ProviderSourceConfiguration) {
        configurations.append(configuration)
        persist()
    }

    func update(_ configuration: ProviderSourceConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index] = configuration
        providerCache[configuration.id] = nil
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        let removed = offsets.map { configurations[$0] }
        for index in offsets.sorted(by: >) { configurations.remove(at: index) }
        for configuration in removed { clearSecrets(for: configuration.id) }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { configurations[$0] }
        for index in source.sorted(by: >) { configurations.remove(at: index) }
        let adjusted = destination - source.filter { $0 < destination }.count
        configurations.insert(contentsOf: moving, at: min(max(adjusted, 0), configurations.count))
        persist()
    }

    func recordConnectionTest(id: UUID, success: Bool, at date: Date = .now) {
        guard var configuration = configuration(id: id) else { return }
        configuration.lastTestAt = date
        configuration.isConnected = success
        if let index = configurations.firstIndex(where: { $0.id == id }) {
            configurations[index] = configuration
            persist()
        }
    }

    func clearSecrets(for sourceID: UUID) {
        for kind in [ProviderSourceConfiguration.SecretKind.apiKey, .password, .accessToken] {
            try? secrets.remove(ProviderSourceConfiguration.secretAccount(sourceID, kind))
        }
        providerCache[sourceID] = nil
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(configurations) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Providers

    func provider(for providerID: ProviderID) -> (any VideoProvider)? {
        if providerID == .builtInHanime { return builtInHanimeProvider }
        guard let configuration = configuration(id: providerID.sourceID),
              configuration.enabled,
              configuration.kind == providerID.kind else { return nil }
        return provider(for: configuration)
    }

    func provider(for configuration: ProviderSourceConfiguration) -> (any VideoProvider)? {
        if configuration.providerID == .builtInHanime { return builtInHanimeProvider }
        guard configuration.kind.isPlayable else { return nil }
        if let cached = providerCache[configuration.id], cached.configuration == configuration {
            return cached.provider
        }
        guard let provider = factory(configuration, secrets) else { return nil }
        providerCache[configuration.id] = (configuration, provider)
        return provider
    }

    /// Enabled sources that can actually play media (not link-only).
    var playableConfigurations: [ProviderSourceConfiguration] {
        configurations.filter { $0.enabled && $0.kind.isPlayable }
    }

    // MARK: - Policy-enforced operations

    func search(_ query: SearchQuery, in providerID: ProviderID) async throws -> SearchPage {
        let (sanitized, blocked) = query.sanitized
        guard !blocked else { return .empty(page: query.page) }
        guard let provider = provider(for: providerID) else {
            throw VideoProviderError.notConfigured("source unavailable")
        }
        let page = try await provider.search(sanitized)
        return SearchPage(
            items: ContentSafetyPolicy.filter(page.items),
            page: page.page,
            hasMore: page.hasMore,
            totalCount: page.totalCount
        )
    }

    /// Searches every enabled playable source except the given kinds
    /// concurrently. Results are de-duplicated by `MediaItemRef`.
    func unifiedSearch(
        _ query: SearchQuery,
        excluding excludedKinds: Set<ProviderKind> = []
    ) async -> (results: [ProviderSearchResult], failures: [ProviderSearchFailure]) {
        let (sanitized, blocked) = query.sanitized
        guard !blocked, !sanitized.text.isEmpty || !sanitized.filters.isEmpty else { return ([], []) }

        let targets: [(name: String, provider: any VideoProvider)] = playableConfigurations
            .filter { !excludedKinds.contains($0.kind) }
            .compactMap { configuration in
                provider(for: configuration).map { (configuration.name, $0) }
            }

        var results: [ProviderSearchResult] = []
        var failures: [ProviderSearchFailure] = []
        await withTaskGroup(of: (String, Result<SearchPage, any Error>).self) { group in
            for target in targets {
                let provider = target.provider
                let name = target.name
                group.addTask {
                    do { return (name, .success(try await provider.search(sanitized))) }
                    catch { return (name, .failure(error)) }
                }
            }
            for await (name, outcome) in group {
                switch outcome {
                case .success(let page):
                    results += ContentSafetyPolicy.filter(page.items).map {
                        ProviderSearchResult(item: $0, sourceName: name)
                    }
                case .failure(let error):
                    failures.append(ProviderSearchFailure(sourceName: name, message: error.localizedDescription))
                }
            }
        }
        var seen = Set<MediaItemRef>()
        results = results.filter { seen.insert($0.item.ref).inserted }
        return (results, failures)
    }

    func home(for providerID: ProviderID) async throws -> [MediaSection] {
        guard let provider = provider(for: providerID) else { throw VideoProviderError.notConfigured("source unavailable") }
        return try await provider.home().compactMap { section in
            let items = ContentSafetyPolicy.filter(section.items)
            return items.isEmpty ? nil : MediaSection(id: section.id, title: section.title, items: items)
        }
    }

    func details(for ref: MediaItemRef) async throws -> MediaItemDetail {
        guard let provider = provider(for: ref.providerID) else { throw VideoProviderError.notConfigured("source unavailable") }
        let detail = try await provider.details(for: ref)
        guard !ContentSafetyPolicy.isBlocked(detail) else { throw VideoProviderError.blockedByContentPolicy }
        return MediaItemDetail(
            summary: detail.summary,
            alternateTitle: detail.alternateTitle,
            overview: detail.overview,
            releaseDate: detail.releaseDate,
            tags: ContentSafetyPolicy.allowedTags(detail.tags),
            studios: detail.studios,
            seriesTitle: detail.seriesTitle,
            seriesRef: detail.seriesRef,
            related: ContentSafetyPolicy.filter(detail.related),
            isFavorite: detail.isFavorite,
            externalURL: detail.externalURL
        )
    }

    func episodes(for ref: MediaItemRef) async throws -> [MediaEpisode] {
        guard let provider = provider(for: ref.providerID) else { throw VideoProviderError.notConfigured("source unavailable") }
        return try await provider.episodes(for: ref).filter { !ContentSafetyPolicy.isBlocked($0.title) }
    }

    /// Streams are only handed out for items that pass the policy, so the
    /// item's details are checked first even if the caller already has them.
    func streams(for ref: MediaItemRef) async throws -> [StreamSource] {
        _ = try await details(for: ref)
        guard let provider = provider(for: ref.providerID) else { throw VideoProviderError.notConfigured("source unavailable") }
        return try await provider.streams(for: ref)
    }

    func markers(for ref: MediaItemRef) async throws -> [Marker] {
        guard let provider = provider(for: ref.providerID) else { return [] }
        return try await provider.markers(for: ref).filter { !ContentSafetyPolicy.isBlocked($0.title) }
    }

    func filters(for providerID: ProviderID) async throws -> FilterSet {
        guard let provider = provider(for: providerID) else { return .empty }
        // FilterSet.init re-applies the policy even if a provider built its own.
        return FilterSet(groups: try await provider.filters().groups)
    }

    func reportPlayback(_ progress: PlaybackProgress) async {
        guard let provider = provider(for: progress.ref.providerID),
              provider.capabilities.contains(.playbackReporting) else { return }
        try? await provider.reportPlayback(progress)
    }

    func testConnection(id: UUID) async -> (success: Bool, message: String) {
        guard let configuration = configuration(id: id) else { return (false, "Unknown source") }
        guard let provider = provider(for: configuration) else {
            return (false, "Source type has no in-app provider")
        }
        let result = await provider.testConnection()
        recordConnectionTest(id: id, success: result.success)
        return result
    }
}
