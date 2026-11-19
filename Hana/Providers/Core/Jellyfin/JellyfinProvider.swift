import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `VideoProvider` backed by a user's own Jellyfin server (REST API,
/// https://api.jellyfin.org). Supports API-key or username/password auth,
/// search/browse, item details, series episodes, playback URLs (direct
/// mp4 or HLS), server-side resume position, chapters → `Marker`, filters,
/// and playback progress reporting.
///
/// Auth uses only the `Authorization: MediaBrowser …` header, which is the
/// one method Jellyfin keeps after removing legacy auth (10.12+). Stream
/// URLs carry no secrets; the header travels in `StreamSource.headers`.
actor JellyfinProvider: VideoProvider {
    nonisolated let id: ProviderID
    nonisolated let displayName: String
    nonisolated let capabilities: ProviderCapabilities = [
        .home, .search, .details, .episodes, .streams, .markers, .filters, .playbackReporting, .downloads,
    ]

    static let clientName = "Hana"
    static let itemFields = "Overview,Genres,Tags,Studios,ProductionYear,PremiereDate,OriginalTitle,Chapters,MediaSources,UserData"
    static let playableItemTypes = "Movie,Series,Episode,Video,MusicVideo"

    private let baseURL: URL
    private let configuration: ProviderSourceConfiguration
    private let secrets: any HanaSecretStore
    private let transport: any ProviderHTTPTransport
    private let deviceID: String
    private let deviceName: String
    private let clientVersion: String
    private var cachedUserID: String?
    private var playSessionIDs: [String: String] = [:]

    init(
        configuration: ProviderSourceConfiguration,
        secrets: any HanaSecretStore,
        transport: any ProviderHTTPTransport = URLSessionProviderTransport(),
        deviceID: String,
        deviceName: String = "iOS",
        clientVersion: String = "1.0"
    ) throws {
        guard let url = URL(string: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil else {
            throw VideoProviderError.notConfigured("invalid server URL")
        }
        self.baseURL = url
        self.configuration = configuration
        self.id = configuration.providerID
        self.displayName = configuration.name
        self.secrets = secrets
        self.transport = transport
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.clientVersion = clientVersion
        self.cachedUserID = configuration.remoteUserID
    }

    // MARK: - VideoProvider

    func home() async throws -> [MediaSection] {
        let userID = try await resolvedUserID()
        async let resume = items(query: [
            "userId": userID, "recursive": "true", "filters": "IsResumable",
            "includeItemTypes": "Movie,Episode,Video,MusicVideo",
            "sortBy": "DatePlayed", "sortOrder": "Descending", "limit": "20",
            "fields": Self.itemFields,
        ])
        async let latest = items(query: [
            "userId": userID, "recursive": "true", "includeItemTypes": Self.playableItemTypes,
            "sortBy": "DateCreated", "sortOrder": "Descending", "limit": "20",
            "fields": Self.itemFields,
        ])
        let (resumeResult, latestResult) = try await (resume, latest)
        return [
            MediaSection(id: "continue", title: "Continue Watching", items: resumeResult.items.map(summary(for:))),
            MediaSection(id: "latest", title: "Recently Added", items: latestResult.items.map(summary(for:))),
        ].filter { !$0.items.isEmpty }
    }

    func search(_ query: SearchQuery) async throws -> SearchPage {
        let userID = try await resolvedUserID()
        var parameters: [String: String] = [
            "userId": userID,
            "recursive": "true",
            "includeItemTypes": Self.playableItemTypes,
            "fields": Self.itemFields,
            "enableImageTypes": "Primary",
            "imageTypeLimit": "1",
            "startIndex": String((query.page - 1) * query.pageSize),
            "limit": String(query.pageSize),
            "sortBy": query.sort ?? (query.text.isEmpty ? "DateCreated" : "SortName"),
            "sortOrder": query.text.isEmpty && query.sort == nil ? "Descending" : "Ascending",
        ]
        if !query.text.isEmpty { parameters["searchTerm"] = query.text }
        if let genres = query.filters["genres"], !genres.isEmpty { parameters["genres"] = genres.joined(separator: "|") }
        if let tags = query.filters["tags"], !tags.isEmpty { parameters["tags"] = tags.joined(separator: "|") }
        if let years = query.filters["years"], !years.isEmpty { parameters["years"] = years.joined(separator: ",") }

        let result = try await items(query: parameters)
        let start = result.startIndex ?? (query.page - 1) * query.pageSize
        let total = result.totalRecordCount
        let hasMore = total.map { start + result.items.count < $0 } ?? (result.items.count == query.pageSize)
        return SearchPage(items: result.items.map(summary(for:)), page: query.page, hasMore: hasMore, totalCount: total)
    }

    func details(for ref: MediaItemRef) async throws -> MediaItemDetail {
        let item = try await item(id: ref.itemID)
        let userID = try await resolvedUserID()
        let similar = (try? await decode(
            JellyfinQueryResult.self,
            path: "Items/\(ref.itemID)/Similar",
            query: ["userId": userID, "limit": "12", "fields": "Genres,Tags"]
        ))?.items ?? []
        return detail(for: item, related: similar)
    }

    func episodes(for ref: MediaItemRef) async throws -> [MediaEpisode] {
        let item = try await item(id: ref.itemID)
        let seriesID: String
        switch item.type {
        case "Series": seriesID = item.id
        case "Episode", "Season":
            guard let id = item.seriesId else { return [] }
            seriesID = id
        default: return []
        }
        let userID = try await resolvedUserID()
        let result = try await decode(
            JellyfinQueryResult.self,
            path: "Shows/\(seriesID)/Episodes",
            query: ["userId": userID, "fields": "Overview,UserData"]
        )
        return result.items.map { episode in
            MediaEpisode(
                ref: itemRef(episode.id),
                title: episode.name ?? "Episode \(episode.indexNumber ?? 0)",
                seasonNumber: episode.parentIndexNumber,
                episodeNumber: episode.indexNumber,
                coverURL: imageURL(for: episode),
                durationSeconds: JellyfinTicks.seconds(episode.runTimeTicks),
                resumePositionSeconds: JellyfinTicks.seconds(episode.userData?.playbackPositionTicks),
                isPlayed: episode.userData?.played ?? false,
                isCurrent: episode.id == ref.itemID
            )
        }
    }

    func streams(for ref: MediaItemRef) async throws -> [StreamSource] {
        let item = try await item(id: ref.itemID)
        guard item.type != "Series", item.type != "Season", item.type != "Folder" else { return [] }
        let headers = ["Authorization": try await authorizationHeader()]
        let sources = item.mediaSources ?? []
        let primary = sources.first
        let mediaSourceID = primary?.id ?? item.id
        let playSessionID = playSessionIDs[item.id] ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        playSessionIDs[item.id] = playSessionID

        var streams: [StreamSource] = []
        let container = (primary?.container ?? item.container ?? "").lowercased()
        let progressiveContainers: Set<String> = ["mp4", "m4v", "mov"]
        let containerIsProgressive = container.split(separator: ",").contains { progressiveContainers.contains(String($0)) }
        if containerIsProgressive, primary?.supportsDirectStream ?? primary?.supportsDirectPlay ?? true,
           let url = makeURL(path: "Videos/\(item.id)/stream", query: [
               "static": "true", "mediaSourceId": mediaSourceID, "deviceId": deviceID,
           ]) {
            streams.append(StreamSource(url: url, kind: .progressive, quality: "Original", mimeType: "video/mp4", headers: headers))
        }
        // HLS transcode/remux fallback that AVPlayer can always play.
        // TODO(jellyfin): replace with POST /Items/{id}/PlaybackInfo + a proper
        // DeviceProfile so the server decides direct play vs. transcode.
        if primary?.supportsTranscoding ?? true,
           let url = makeURL(path: "Videos/\(item.id)/master.m3u8", query: [
               "mediaSourceId": mediaSourceID,
               "deviceId": deviceID,
               "playSessionId": playSessionID,
               "videoCodec": "hevc,h264",
               "audioCodec": "aac,mp3,ac3,eac3",
               "segmentContainer": "mp4",
               "transcodingMaxAudioChannels": "2",
           ]) {
            streams.append(StreamSource(url: url, kind: .hls, quality: "Auto (HLS)", mimeType: "application/vnd.apple.mpegurl", headers: headers, isDownloadable: false))
        }
        return streams
    }

    func markers(for ref: MediaItemRef) async throws -> [Marker] {
        let item = try await item(id: ref.itemID)
        return Self.markers(from: item)
    }

    func filters() async throws -> FilterSet {
        let userID = try await resolvedUserID()
        let filters = try await decode(
            JellyfinQueryFilters.self,
            path: "Items/Filters",
            query: ["userId": userID, "includeItemTypes": Self.playableItemTypes, "recursive": "true"]
        )
        return FilterSet(groups: [
            FilterGroup(id: "genres", title: "Genres", selection: .multiple,
                        options: (filters.genres ?? []).map { FilterOption(title: $0, value: $0) }),
            FilterGroup(id: "tags", title: "Tags", selection: .multiple,
                        options: (filters.tags ?? []).map { FilterOption(title: $0, value: $0) }),
            FilterGroup(id: "years", title: "Year", selection: .single,
                        options: (filters.years ?? []).sorted(by: >).map { FilterOption(title: String($0), value: String($0)) }),
        ])
    }

    func reportPlayback(_ progress: PlaybackProgress) async throws {
        let path: String
        switch progress.event {
        case .started: path = "Sessions/Playing"
        case .progress: path = "Sessions/Playing/Progress"
        case .stopped: path = "Sessions/Playing/Stopped"
        }
        var body: [String: Any] = [
            "ItemId": progress.ref.itemID,
            "PositionTicks": JellyfinTicks.ticks(seconds: progress.positionSeconds),
            "IsPaused": progress.isPaused,
            "CanSeek": true,
        ]
        if let playSessionID = playSessionIDs[progress.ref.itemID] { body["PlaySessionId"] = playSessionID }
        let data = try JSONSerialization.data(withJSONObject: body)
        _ = try await send(path: path, method: "POST", body: data, expecting: 200..<300)
        if progress.event == .stopped { playSessionIDs[progress.ref.itemID] = nil }
    }

    func testConnection() async -> (success: Bool, message: String) {
        do {
            let info = try await decode(JellyfinPublicSystemInfo.self, path: "System/Info/Public", query: [:], authenticated: false)
            let userID = try await resolvedUserID()
            _ = try await items(query: ["userId": userID, "limit": "1", "recursive": "true"])
            let name = info.serverName ?? baseURL.host ?? "Jellyfin"
            return (true, "Connected to \(name)\(info.version.map { " (Jellyfin \($0))" } ?? "")")
        } catch {
            return (false, "Connection failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Mapping (static so it can be unit-tested without a server)

    nonisolated static func markers(from item: JellyfinItem) -> [Marker] {
        (item.chapters ?? []).compactMap { chapter in
            guard let ticks = chapter.startPositionTicks else { return nil }
            return Marker(positionMilliseconds: ticks / 10_000, title: chapter.name, source: .provider)
        }
        .sorted { $0.positionMilliseconds < $1.positionMilliseconds }
    }

    nonisolated static func kind(for type: String?) -> MediaItemKind {
        switch type {
        case "Movie": .movie
        case "Series": .series
        case "Season": .season
        case "Episode": .episode
        case "Video", "MusicVideo": .video
        case "Folder", "CollectionFolder", "BoxSet": .folder
        default: .other
        }
    }

    func summary(for item: JellyfinItem) -> MediaItemSummary {
        Self.summary(for: item, providerID: id, baseURL: baseURL)
    }

    nonisolated static func summary(for item: JellyfinItem, providerID: ProviderID, baseURL: URL) -> MediaItemSummary {
        let subtitle: String?
        if item.type == "Episode", let series = item.seriesName {
            let code = [item.parentIndexNumber.map { "S\($0)" }, item.indexNumber.map { "E\($0)" }].compactMap { $0 }.joined()
            subtitle = code.isEmpty ? series : "\(series) · \(code)"
        } else {
            subtitle = item.productionYear.map(String.init)
        }
        return MediaItemSummary(
            ref: MediaItemRef(providerID: providerID, itemID: item.id),
            title: item.name ?? "Untitled",
            kind: kind(for: item.type),
            coverURL: imageURL(for: item, baseURL: baseURL),
            durationSeconds: JellyfinTicks.seconds(item.runTimeTicks),
            subtitle: subtitle,
            tags: (item.genres ?? []) + (item.tags ?? []),
            resumePositionSeconds: JellyfinTicks.seconds(item.userData?.playbackPositionTicks),
            isPlayed: item.userData?.played ?? false
        )
    }

    func detail(for item: JellyfinItem, related: [JellyfinItem]) -> MediaItemDetail {
        MediaItemDetail(
            summary: summary(for: item),
            alternateTitle: item.originalTitle.flatMap { $0 == item.name ? nil : $0 },
            overview: item.overview,
            releaseDate: JellyfinDate.parse(item.premiereDate),
            tags: (item.genres ?? []) + (item.tags ?? []),
            studios: (item.studios ?? []).compactMap(\.name),
            seriesTitle: item.seriesName,
            seriesRef: item.seriesId.map(itemRef),
            related: related.map(summary(for:)),
            isFavorite: item.userData?.isFavorite ?? false,
            externalURL: makeWebURL(itemID: item.id)
        )
    }

    nonisolated static func imageURL(for item: JellyfinItem, baseURL: URL) -> URL? {
        let imageItemID: String
        let tag: String
        if let primaryTag = item.imageTags?["Primary"] {
            imageItemID = item.id
            tag = primaryTag
        } else if let seriesID = item.seriesId, let seriesTag = item.seriesPrimaryImageTag {
            imageItemID = seriesID
            tag = seriesTag
        } else {
            return nil
        }
        // Image endpoints don't require auth, so Nuke can load these directly.
        return makeURL(baseURL: baseURL, path: "Items/\(imageItemID)/Images/Primary", query: [
            "tag": tag, "maxWidth": "600", "quality": "90",
        ])
    }

    private func imageURL(for item: JellyfinItem) -> URL? {
        Self.imageURL(for: item, baseURL: baseURL)
    }

    private func itemRef(_ itemID: String) -> MediaItemRef {
        MediaItemRef(providerID: id, itemID: itemID)
    }

    private func makeWebURL(itemID: String) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path.hasSuffix("/") == true ? String(components?.path.dropLast() ?? "") : (components?.path ?? "")
        components?.path = basePath + "/web/"
        components?.fragment = "/details?id=\(itemID)"
        return components?.url
    }

    // MARK: - Auth

    /// `Authorization: MediaBrowser Client="Hana", Device=…, DeviceId=…, Version=…[, Token=…]`
    nonisolated static func authorizationHeader(client: String, device: String, deviceID: String, version: String, token: String?) -> String {
        func quoted(_ value: String) -> String {
            "\"\(value.replacingOccurrences(of: "\"", with: "'"))\""
        }
        var parts = [
            "Client=\(quoted(client))",
            "Device=\(quoted(device))",
            "DeviceId=\(quoted(deviceID))",
            "Version=\(quoted(version))",
        ]
        if let token, !token.isEmpty { parts.append("Token=\(quoted(token))") }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    private func authorizationHeader(token explicitToken: String? = nil) async throws -> String {
        let token: String
        if let explicitToken {
            token = explicitToken
        } else {
            token = try await accessToken()
        }
        return Self.authorizationHeader(client: Self.clientName, device: deviceName, deviceID: deviceID, version: clientVersion, token: token)
    }

    private func accessToken() async throws -> String {
        switch configuration.authMethod {
        case .apiKey:
            guard let key = try secrets.string(for: configuration.secretAccount(.apiKey)), !key.isEmpty else {
                throw VideoProviderError.notConfigured("missing API key")
            }
            return key
        case .password:
            if let token = try secrets.string(for: configuration.secretAccount(.accessToken)), !token.isEmpty {
                return token
            }
            return try await signIn()
        case .none:
            throw VideoProviderError.notConfigured("choose API key or password sign-in")
        }
    }

    /// POST /Users/AuthenticateByName; stores the access token in the Keychain.
    @discardableResult
    private func signIn() async throws -> String {
        guard let username = configuration.username, !username.isEmpty else {
            throw VideoProviderError.notConfigured("missing user name")
        }
        let password = try secrets.string(for: configuration.secretAccount(.password)) ?? ""
        let body = try JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])
        let header = Self.authorizationHeader(client: Self.clientName, device: deviceName, deviceID: deviceID, version: clientVersion, token: nil)
        let data: Data
        do {
            data = try await send(path: "Users/AuthenticateByName", method: "POST", body: body, authorization: header, expecting: 200..<300)
        } catch VideoProviderError.httpStatus(let code) where code == 401 || code == 403 {
            throw VideoProviderError.authenticationFailed
        }
        let result = try JSONDecoder().decode(JellyfinAuthenticationResult.self, from: data)
        guard let token = result.accessToken, !token.isEmpty else { throw VideoProviderError.authenticationFailed }
        try secrets.setString(token, for: configuration.secretAccount(.accessToken))
        if let userID = result.user?.id { cachedUserID = userID }
        return token
    }

    private func resolvedUserID() async throws -> String {
        if let cachedUserID { return cachedUserID }
        if configuration.authMethod == .password {
            // A fresh sign-in returns the user; with a cached token use /Users/Me.
            if let me = try? await decode(JellyfinUser.self, path: "Users/Me", query: [:]) {
                cachedUserID = me.id
                return me.id
            }
            try await signIn()
            if let cachedUserID { return cachedUserID }
        }
        // API keys are not bound to a user: pick the configured user name, or
        // the first enabled user.
        let users = try await decode([JellyfinUser].self, path: "Users", query: [:])
        let wanted = configuration.username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let enabled = users.filter { $0.policy?.isDisabled != true }
        let match = wanted.flatMap { name in enabled.first { $0.name?.lowercased() == name } } ?? enabled.first
        guard let user = match else { throw VideoProviderError.notConfigured("no Jellyfin user available") }
        cachedUserID = user.id
        return user.id
    }

    // MARK: - HTTP

    private func item(id itemID: String) async throws -> JellyfinItem {
        let userID = try await resolvedUserID()
        return try await decode(JellyfinItem.self, path: "Items/\(itemID)", query: ["userId": userID, "fields": Self.itemFields])
    }

    private func items(query: [String: String]) async throws -> JellyfinQueryResult {
        try await decode(JellyfinQueryResult.self, path: "Items", query: query)
    }

    private func decode<T: Decodable>(_ type: T.Type, path: String, query: [String: String], authenticated: Bool = true) async throws -> T {
        let data = try await send(path: path, method: "GET", query: query, authenticated: authenticated, expecting: 200..<300)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw VideoProviderError.invalidResponse
        }
    }

    private func send(
        path: String,
        method: String,
        query: [String: String] = [:],
        body: Data? = nil,
        authorization: String? = nil,
        authenticated: Bool = true,
        expecting okRange: Range<Int>,
        isRetry: Bool = false
    ) async throws -> Data {
        guard let url = makeURL(path: path, query: query) else { throw VideoProviderError.notConfigured("invalid server URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        } else if authenticated {
            request.setValue(try await authorizationHeader(), forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 401, authenticated, authorization == nil, !isRetry, configuration.authMethod == .password {
            // Token revoked/expired: drop it and sign in again once.
            try? secrets.remove(configuration.secretAccount(.accessToken))
            try await signIn()
            return try await send(path: path, method: method, query: query, body: body, authenticated: authenticated, expecting: okRange, isRetry: true)
        }
        if response.statusCode == 404 { throw VideoProviderError.itemNotFound }
        if response.statusCode == 401 || response.statusCode == 403 {
            if authenticated, authorization == nil { throw VideoProviderError.authenticationFailed }
        }
        guard okRange.contains(response.statusCode) else { throw VideoProviderError.httpStatus(response.statusCode) }
        return data
    }

    private func makeURL(path: String, query: [String: String]) -> URL? {
        Self.makeURL(baseURL: baseURL, path: path, query: query)
    }

    nonisolated static func makeURL(baseURL: URL, path: String, query: [String: String]) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        var basePath = components.path
        while basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + "/" + path
        let items = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items.isEmpty ? nil : items
        components.fragment = nil
        return components.url
    }
}
