import Foundation

// Shared, provider-agnostic models for the VideoProvider layer.
//
// Everything in Hana/Providers/Core is Foundation-only so it compiles in the
// app target (default MainActor isolation) and in the `HanaProviderCore`
// SwiftPM target used for Linux/CI unit tests. Types are explicitly
// `nonisolated` + `Sendable` so they can cross actor boundaries freely.

/// Stable identifier of a provider *kind* plus the configured source instance.
/// `kind` selects the implementation, `sourceID` distinguishes two Jellyfin
/// servers (for example) from each other.
nonisolated struct ProviderID: Hashable, Codable, Sendable, CustomStringConvertible {
    var kind: ProviderKind
    var sourceID: UUID

    init(kind: ProviderKind, sourceID: UUID) {
        self.kind = kind
        self.sourceID = sourceID
    }

    /// The built-in Hanime-style site keeps a fixed source ID so history keys
    /// stay stable across reinstalls/backups.
    static let builtInHanime = ProviderID(
        kind: .hanime,
        sourceID: UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
    )

    var description: String { "\(kind.rawValue):\(sourceID.uuidString.lowercased())" }
}

nonisolated enum ProviderKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// Hanime-style HTML site handled by HanimeRepository/HanimeHTMLParser.
    case hanime
    /// Self-hosted Jellyfin server (the user's own library).
    case jellyfin
    /// Legacy link-only search sources kept for compatibility with `hana.sources.v1`.
    case genericLink
    case feedLink
    case hentaiAtHomeLink

    var isPlayable: Bool {
        switch self {
        case .hanime, .jellyfin: true
        case .genericLink, .feedLink, .hentaiAtHomeLink: false
        }
    }
}

/// A reference to one item inside one provider. This replaces the bare
/// `videoCode` string as the identity of a piece of media.
nonisolated struct MediaItemRef: Hashable, Codable, Sendable, CustomStringConvertible {
    var providerID: ProviderID
    var itemID: String

    init(providerID: ProviderID, itemID: String) {
        self.providerID = providerID
        self.itemID = itemID
    }

    /// Wraps a legacy Hanime `videoCode` so existing SwiftData rows can be keyed
    /// as `(provider, item)` without losing data.
    static func legacyHanime(videoCode: String) -> MediaItemRef {
        MediaItemRef(providerID: .builtInHanime, itemID: videoCode)
    }

    /// Flat string key suitable for `@Attribute(.unique)` columns:
    /// `<kind>:<sourceUUID>:<itemID>`. Legacy Hanime rows use the bare
    /// `videoCode` so the V1 → V2 migration is a no-op for them.
    var storageKey: String {
        if providerID == .builtInHanime { return itemID }
        return "\(providerID.kind.rawValue):\(providerID.sourceID.uuidString.lowercased()):\(itemID)"
    }

    init?(storageKey: String) {
        let parts = storageKey.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        if parts.count == 3,
           let kind = ProviderKind(rawValue: String(parts[0])),
           let sourceID = UUID(uuidString: String(parts[1])),
           !parts[2].isEmpty {
            self.init(providerID: ProviderID(kind: kind, sourceID: sourceID), itemID: String(parts[2]))
            return
        }
        let trimmed = storageKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(":") else { return nil }
        self = .legacyHanime(videoCode: trimmed)
    }

    var description: String { storageKey }
}

nonisolated enum MediaItemKind: String, Codable, Sendable, Hashable {
    case video
    case movie
    case series
    case season
    case episode
    case folder
    case other
}

nonisolated struct MediaItemSummary: Identifiable, Hashable, Sendable {
    var id: MediaItemRef { ref }

    let ref: MediaItemRef
    let title: String
    let kind: MediaItemKind
    let coverURL: URL?
    let durationSeconds: TimeInterval?
    let subtitle: String?
    let tags: [String]
    /// Server-side resume position (seconds), when the provider tracks it.
    let resumePositionSeconds: TimeInterval?
    let isPlayed: Bool

    init(
        ref: MediaItemRef,
        title: String,
        kind: MediaItemKind = .video,
        coverURL: URL? = nil,
        durationSeconds: TimeInterval? = nil,
        subtitle: String? = nil,
        tags: [String] = [],
        resumePositionSeconds: TimeInterval? = nil,
        isPlayed: Bool = false
    ) {
        self.ref = ref
        self.title = title
        self.kind = kind
        self.coverURL = coverURL
        self.durationSeconds = durationSeconds
        self.subtitle = subtitle
        self.tags = tags
        self.resumePositionSeconds = resumePositionSeconds
        self.isPlayed = isPlayed
    }
}

nonisolated struct MediaEpisode: Identifiable, Hashable, Sendable {
    var id: MediaItemRef { ref }

    let ref: MediaItemRef
    let title: String
    let seasonNumber: Int?
    let episodeNumber: Int?
    let coverURL: URL?
    let durationSeconds: TimeInterval?
    let resumePositionSeconds: TimeInterval?
    let isPlayed: Bool
    let isCurrent: Bool
}

nonisolated struct MediaItemDetail: Hashable, Sendable {
    let summary: MediaItemSummary
    let alternateTitle: String?
    let overview: String?
    let releaseDate: Date?
    let tags: [String]
    let studios: [String]
    let seriesTitle: String?
    let seriesRef: MediaItemRef?
    let related: [MediaItemSummary]
    let isFavorite: Bool
    let externalURL: URL?

    var ref: MediaItemRef { summary.ref }
    var title: String { summary.title }
}

nonisolated struct MediaSection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let items: [MediaItemSummary]
}

nonisolated enum StreamKind: String, Codable, Sendable, Hashable {
    case progressive   // mp4 / mov / m4v, playable with AVPlayer directly
    case hls           // m3u8
    case other
}

/// Everything AVPlayer needs to start playback: URL plus the HTTP headers that
/// must be sent with every request (passed via `AVURLAssetHTTPHeaderFieldsKey`).
nonisolated struct StreamSource: Identifiable, Hashable, Sendable {
    var id: String { "\(quality)-\(url.absoluteString)" }

    let url: URL
    let kind: StreamKind
    let quality: String
    let mimeType: String?
    let headers: [String: String]
    let isDownloadable: Bool

    init(url: URL, kind: StreamKind, quality: String, mimeType: String? = nil, headers: [String: String] = [:], isDownloadable: Bool = true) {
        self.url = url
        self.kind = kind
        self.quality = quality
        self.mimeType = mimeType
        self.headers = headers
        self.isDownloadable = isDownloadable
    }

    static func inferKind(url: URL, mimeType: String?) -> StreamKind {
        let mime = mimeType?.lowercased() ?? ""
        let ext = url.pathExtension.lowercased()
        if ext == "m3u8" || mime.contains("mpegurl") { return .hls }
        if ["mp4", "m4v", "mov"].contains(ext) || mime.hasPrefix("video/mp4") || mime.hasPrefix("video/quicktime") {
            return .progressive
        }
        return .other
    }
}

/// A timestamp marker. Hana's HKeyframes, Jellyfin chapters and (later) Stash
/// scene markers all map onto this.
nonisolated struct Marker: Identifiable, Hashable, Sendable, Codable {
    var id: String { "\(positionMilliseconds)-\(title ?? "")" }

    let positionMilliseconds: Int64
    let title: String?
    let source: Source

    nonisolated enum Source: String, Codable, Sendable, Hashable {
        case provider     // e.g. Jellyfin chapters
        case localLibrary // user-created HKeyframes
        case sharedLibrary
    }

    var seconds: TimeInterval { TimeInterval(positionMilliseconds) / 1_000 }

    init(positionMilliseconds: Int64, title: String?, source: Source) {
        self.positionMilliseconds = max(positionMilliseconds, 0)
        self.title = title
        self.source = source
    }
}

nonisolated struct FilterOption: Identifiable, Hashable, Sendable {
    var id: String { value }
    let title: String
    let value: String
}

nonisolated struct FilterGroup: Identifiable, Hashable, Sendable {
    enum Selection: String, Sendable, Hashable { case single, multiple }

    let id: String
    let title: String
    let selection: Selection
    let options: [FilterOption]
}

/// Filters a provider offers. Construct through `init(groups:)`, which always
/// runs the options through `ContentSafetyPolicy`; there is no way to build a
/// FilterSet that contains blocked options.
nonisolated struct FilterSet: Hashable, Sendable {
    let groups: [FilterGroup]

    init(groups: [FilterGroup]) {
        self.groups = groups.compactMap { group in
            let options = group.options.filter { option in
                !ContentSafetyPolicy.isBlocked(option.title) && !ContentSafetyPolicy.isBlocked(option.value)
            }
            guard !options.isEmpty else { return nil }
            return FilterGroup(id: group.id, title: group.title, selection: group.selection, options: options)
        }
    }

    static let empty = FilterSet(groups: [])
}

nonisolated struct SearchQuery: Hashable, Sendable {
    var text: String
    /// Selected filter values keyed by `FilterGroup.id`.
    var filters: [String: [String]]
    var sort: String?
    var page: Int
    var pageSize: Int

    init(text: String, filters: [String: [String]] = [:], sort: String? = nil, page: Int = 1, pageSize: Int = 30) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.filters = filters
        self.sort = sort
        self.page = max(page, 1)
        self.pageSize = max(pageSize, 1)
    }

    /// Same query with any blocked text/filter values removed.
    /// `isBlocked` is true when the free-text query itself is blocked; providers
    /// must return an empty page in that case.
    var sanitized: (query: SearchQuery, isBlocked: Bool) {
        var copy = self
        copy.filters = filters.mapValues { values in values.filter { !ContentSafetyPolicy.isBlocked($0) } }
            .filter { !$0.value.isEmpty }
        return (copy, ContentSafetyPolicy.isBlocked(text))
    }
}

nonisolated struct SearchPage: Hashable, Sendable {
    let items: [MediaItemSummary]
    let page: Int
    let hasMore: Bool
    let totalCount: Int?

    static func empty(page: Int = 1) -> SearchPage {
        SearchPage(items: [], page: page, hasMore: false, totalCount: 0)
    }
}

nonisolated struct PlaybackProgress: Hashable, Sendable {
    enum Event: String, Sendable { case started, progress, stopped }

    let ref: MediaItemRef
    let positionSeconds: TimeInterval
    let isPaused: Bool
    let event: Event
}

nonisolated struct ProviderCapabilities: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let home = ProviderCapabilities(rawValue: 1 << 0)
    static let search = ProviderCapabilities(rawValue: 1 << 1)
    static let details = ProviderCapabilities(rawValue: 1 << 2)
    static let episodes = ProviderCapabilities(rawValue: 1 << 3)
    static let streams = ProviderCapabilities(rawValue: 1 << 4)
    static let markers = ProviderCapabilities(rawValue: 1 << 5)
    static let filters = ProviderCapabilities(rawValue: 1 << 6)
    static let playbackReporting = ProviderCapabilities(rawValue: 1 << 7)
    static let downloads = ProviderCapabilities(rawValue: 1 << 8)
}

nonisolated enum MediaDuration {
    /// Parses clock strings like "12:34" or "1:02:03" (as shown on Hanime-style
    /// cards) into seconds.
    static func seconds(fromClock text: String?) -> TimeInterval? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let parts = text.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        return TimeInterval(parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 })
    }
}
