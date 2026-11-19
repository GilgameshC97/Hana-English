import Foundation

/// `VideoProvider` adapter over the existing Hanime-style stack
/// (`HanimeRepository` + `HanimeHTMLParser` via `HanaHTTPClient`).
///
/// The repository and HTTP client are MainActor-isolated (the app target uses
/// default MainActor isolation), so every protocol witness is `nonisolated`
/// and immediately hops to a MainActor helper. This pattern is exercised by
/// `MainActorPatternProvider` in Tests/HanaProviderCoreTests.
final class HanimeProvider: VideoProvider {
    nonisolated let id: ProviderID
    nonisolated let displayName: String
    nonisolated let capabilities: ProviderCapabilities = [
        .home, .search, .details, .episodes, .streams, .markers, .filters, .downloads,
    ]

    private let repository: HanimeRepository
    private let httpClient: HanaHTTPClient

    init(
        repository: HanimeRepository,
        httpClient: HanaHTTPClient,
        id: ProviderID = .builtInHanime,
        displayName: String = "Hanime1"
    ) {
        self.repository = repository
        self.httpClient = httpClient
        self.id = id
        self.displayName = displayName
    }

    // MARK: VideoProvider (nonisolated entry points)

    nonisolated func home() async throws -> [MediaSection] { try await loadHome() }
    nonisolated func search(_ query: SearchQuery) async throws -> SearchPage { try await performSearch(query) }
    nonisolated func details(for ref: MediaItemRef) async throws -> MediaItemDetail { try await loadDetails(ref) }
    nonisolated func episodes(for ref: MediaItemRef) async throws -> [MediaEpisode] { try await loadEpisodes(ref) }
    nonisolated func streams(for ref: MediaItemRef) async throws -> [StreamSource] { try await loadStreams(ref) }
    nonisolated func markers(for ref: MediaItemRef) async throws -> [Marker] { await loadSharedMarkers(ref) }
    nonisolated func filters() async throws -> FilterSet { await buildFilters() }
    nonisolated func testConnection() async -> (success: Bool, message: String) { await checkConnection() }

    // MARK: MainActor implementations

    private func loadHome() async throws -> [MediaSection] {
        let page = try await repository.homePage()
        return page.sections.map { section in
            MediaSection(id: section.key, title: section.title, items: section.videos.map(summary(for:)))
        }
    }

    private func performSearch(_ query: SearchQuery) async throws -> SearchPage {
        var criteria = HanimeSearchCriteria(query: query.text)
        criteria.genre = query.filters["genre"]?.first
        criteria.sort = query.sort ?? query.filters["sort"]?.first
        criteria.date = query.filters["date"]?.first
        criteria.duration = query.filters["duration"]?.first
        criteria.tags = query.filters["tags"] ?? []
        criteria.brands = query.filters["brands"] ?? []
        let videos = try await repository.search(criteria: criteria, page: query.page)
        return SearchPage(items: videos.map(summary(for:)), page: query.page, hasMore: !videos.isEmpty, totalCount: nil)
    }

    private func loadDetails(_ ref: MediaItemRef) async throws -> MediaItemDetail {
        let video = try await repository.video(code: ref.itemID)
        let summary = MediaItemSummary(
            ref: itemRef(video.videoCode),
            title: video.title,
            kind: .video,
            coverURL: video.coverURL,
            subtitle: video.artist?.name,
            tags: video.tags
        )
        return MediaItemDetail(
            summary: summary,
            alternateTitle: video.chineseTitle,
            overview: video.introduction,
            releaseDate: video.uploadTime,
            tags: video.tags,
            studios: video.artist.map { [$0.name] } ?? [],
            seriesTitle: video.series?.title,
            // TODO(hanime): series have no standalone page on the site; expose
            // them through episodes(for:) instead of a seriesRef.
            seriesRef: nil,
            related: video.relatedVideos.map(summary(for:)),
            isFavorite: video.isFavorite,
            externalURL: watchURL(code: video.videoCode)
        )
    }

    private func loadEpisodes(_ ref: MediaItemRef) async throws -> [MediaEpisode] {
        let video = try await repository.video(code: ref.itemID)
        guard let series = video.series else { return [] }
        return series.videos.enumerated().map { index, item in
            MediaEpisode(
                ref: itemRef(item.videoCode),
                title: item.title,
                seasonNumber: nil,
                episodeNumber: index + 1,
                coverURL: item.coverURL,
                durationSeconds: MediaDuration.seconds(fromClock: item.duration),
                resumePositionSeconds: nil,
                isPlayed: false,
                isCurrent: item.isCurrent
            )
        }
    }

    private func loadStreams(_ ref: MediaItemRef) async throws -> [StreamSource] {
        let video = try await repository.video(code: ref.itemID)
        return video.resolutions.map { link in
            StreamSource(
                url: link.url,
                kind: StreamSource.inferKind(url: link.url, mimeType: link.mimeType),
                quality: link.quality,
                mimeType: link.mimeType,
                headers: httpClient.mediaHeaders(for: link.url)
            )
        }
    }

    /// Bundled shared HKeyframes. User-created keyframes live in SwiftData
    /// (`HKeyframeRecord`) and are merged by the view layer, which owns the
    /// ModelContext.
    private func loadSharedMarkers(_ ref: MediaItemRef) -> [Marker] {
        guard let record = HanaHKeyframeLibrary.sharedRecord(videoCode: ref.itemID) else { return [] }
        return record.entries.map {
            Marker(positionMilliseconds: $0.positionMilliseconds, title: $0.prompt, source: .sharedLibrary)
        }
    }

    private func buildFilters() -> FilterSet {
        func group(_ id: String, _ title: String, _ selection: FilterGroup.Selection, _ options: [HanimeSearchOption]) -> FilterGroup {
            FilterGroup(id: id, title: title, selection: selection, options: options.compactMap { option in
                option.value.map { FilterOption(title: option.title, value: $0) }
            })
        }
        var groups = [
            group("genre", "Genre", .single, HanimeSearchCriteria.genres),
            group("sort", "Sort", .single, HanimeSearchCriteria.sortOptions),
            group("date", "Date", .single, HanimeSearchCriteria.dateOptions),
            group("duration", "Duration", .single, HanimeSearchCriteria.durationOptions),
        ]
        for section in HanimeSearchOptionCatalog.tagSections {
            groups.append(FilterGroup(
                id: "tags",
                title: section.title,
                selection: .multiple,
                options: section.options.compactMap { option in option.value.map { FilterOption(title: option.title, value: $0) } }
            ))
        }
        for section in HanimeSearchOptionCatalog.brandSections {
            groups.append(group("brands", section.title, .multiple, section.options))
        }
        return FilterSet(groups: groups)
    }

    private func checkConnection() async -> (success: Bool, message: String) {
        do {
            _ = try await repository.homePage()
            return (true, "Connected")
        } catch {
            return (false, "Connection failed: \(error.localizedDescription)")
        }
    }

    // MARK: Mapping

    private func summary(for info: HanimeInfo) -> MediaItemSummary {
        MediaItemSummary(
            ref: itemRef(info.videoCode),
            title: info.title,
            kind: .video,
            coverURL: info.coverURL,
            durationSeconds: MediaDuration.seconds(fromClock: info.duration),
            subtitle: info.artist
        )
    }

    private func itemRef(_ code: String) -> MediaItemRef {
        MediaItemRef(providerID: id, itemID: code)
    }

    private func watchURL(code: String) -> URL? {
        var components = URLComponents(url: httpClient.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/watch"
        components?.queryItems = [URLQueryItem(name: "v", value: code)]
        return components?.url
    }
}
