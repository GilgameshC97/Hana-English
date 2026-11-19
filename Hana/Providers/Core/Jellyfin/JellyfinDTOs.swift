import Foundation

// Minimal Codable mirrors of the Jellyfin REST API (10.9+ OpenAPI schema,
// https://api.jellyfin.org). Only fields Hana uses are declared; everything is
// optional so newer/older servers decode without failing.

nonisolated struct JellyfinQueryResult: Decodable, Sendable {
    let items: [JellyfinItem]
    let totalRecordCount: Int?
    let startIndex: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([JellyfinItem].self, forKey: .items) ?? []
        totalRecordCount = try container.decodeIfPresent(Int.self, forKey: .totalRecordCount)
        startIndex = try container.decodeIfPresent(Int.self, forKey: .startIndex)
    }
}

nonisolated struct JellyfinItem: Decodable, Sendable {
    let id: String
    let name: String?
    let originalTitle: String?
    let type: String?
    let overview: String?
    let genres: [String]?
    let tags: [String]?
    let studios: [JellyfinNameID]?
    let runTimeTicks: Int64?
    let productionYear: Int?
    let premiereDate: String?
    let seriesId: String?
    let seriesName: String?
    let seasonId: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let imageTags: [String: String]?
    let seriesPrimaryImageTag: String?
    let userData: JellyfinUserData?
    let chapters: [JellyfinChapter]?
    let mediaSources: [JellyfinMediaSource]?
    let container: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case originalTitle = "OriginalTitle"
        case type = "Type"
        case overview = "Overview"
        case genres = "Genres"
        case tags = "Tags"
        case studios = "Studios"
        case runTimeTicks = "RunTimeTicks"
        case productionYear = "ProductionYear"
        case premiereDate = "PremiereDate"
        case seriesId = "SeriesId"
        case seriesName = "SeriesName"
        case seasonId = "SeasonId"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case imageTags = "ImageTags"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case userData = "UserData"
        case chapters = "Chapters"
        case mediaSources = "MediaSources"
        case container = "Container"
    }
}

nonisolated struct JellyfinNameID: Decodable, Sendable {
    let name: String?
    let id: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
    }
}

nonisolated struct JellyfinUserData: Decodable, Sendable {
    let playbackPositionTicks: Int64?
    let played: Bool?
    let isFavorite: Bool?
    let playedPercentage: Double?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case played = "Played"
        case isFavorite = "IsFavorite"
        case playedPercentage = "PlayedPercentage"
    }
}

nonisolated struct JellyfinChapter: Decodable, Sendable {
    let startPositionTicks: Int64?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case startPositionTicks = "StartPositionTicks"
        case name = "Name"
    }
}

nonisolated struct JellyfinMediaSource: Decodable, Sendable {
    let id: String?
    let container: String?
    let name: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let supportsTranscoding: Bool?
    let bitrate: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case container = "Container"
        case name = "Name"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case bitrate = "Bitrate"
    }
}

nonisolated struct JellyfinAuthenticationResult: Decodable, Sendable {
    let user: JellyfinUser?
    let accessToken: String?
    let serverId: String?

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
        case serverId = "ServerId"
    }
}

nonisolated struct JellyfinUser: Decodable, Sendable {
    let id: String
    let name: String?
    let policy: Policy?

    nonisolated struct Policy: Decodable, Sendable {
        let isDisabled: Bool?
        let isAdministrator: Bool?

        enum CodingKeys: String, CodingKey {
            case isDisabled = "IsDisabled"
            case isAdministrator = "IsAdministrator"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case policy = "Policy"
    }
}

nonisolated struct JellyfinPublicSystemInfo: Decodable, Sendable {
    let serverName: String?
    let version: String?
    let id: String?

    enum CodingKeys: String, CodingKey {
        case serverName = "ServerName"
        case version = "Version"
        case id = "Id"
    }
}

nonisolated struct JellyfinQueryFilters: Decodable, Sendable {
    let genres: [String]?
    let tags: [String]?
    let years: [Int]?

    enum CodingKeys: String, CodingKey {
        case genres = "Genres"
        case tags = "Tags"
        case years = "Years"
    }
}

nonisolated enum JellyfinTicks {
    /// Jellyfin positions are .NET ticks (100 ns).
    static let perSecond: Double = 10_000_000

    static func seconds(_ ticks: Int64?) -> TimeInterval? {
        guard let ticks, ticks > 0 else { return nil }
        return Double(ticks) / perSecond
    }

    static func ticks(seconds: TimeInterval) -> Int64 {
        Int64((max(seconds, 0) * perSecond).rounded())
    }
}

nonisolated enum JellyfinDate {
    /// Parses Jellyfin's ISO dates, which may carry 7 fractional digits
    /// (e.g. `2021-04-02T00:00:00.0000000Z`) that ISO8601DateFormatter rejects.
    static func parse(_ string: String?) -> Date? {
        guard let string, string.count >= 10 else { return nil }
        let dayPart = String(string.prefix(10))
        let parts = dayPart.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return components.date
    }
}
