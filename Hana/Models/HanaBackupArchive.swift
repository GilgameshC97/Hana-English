import Foundation

nonisolated struct HanaBackupArchive: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String
    var buildNumber: String
    var settings: HanaBackupSettings
    var watchHistory: [HanaBackupWatchHistory]
    var searchHistory: [HanaBackupSearchHistory]
    var advancedSearchHistory: [HanaBackupAdvancedSearchHistory]
    var favorites: [HanaBackupFavorite]
    var watchLater: [HanaBackupWatchLater]
    var playlists: [HanaBackupPlaylist]
    var playlistItems: [HanaBackupPlaylistItem]
    var downloadQueue: [HanaBackupDownload]
    var downloadGroups: [HanaBackupDownloadGroup]
    var hKeyframes: [HanaBackupHKeyframe]

    static func encode(_ archive: HanaBackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601String(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> HanaBackupArchive {
        do {
            let header = try JSONDecoder().decode(HanaBackupHeader.self, from: data)
            guard header.schemaVersion == currentSchemaVersion else {
                throw HanaBackupError.unsupportedSchemaVersion(header.schemaVersion)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                guard let date = date(fromISO8601: value) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Invalid ISO 8601 date: \(value)"
                    )
                }
                return date
            }
            return try decoder.decode(HanaBackupArchive.self, from: data)
        } catch let error as HanaBackupError {
            throw error
        } catch {
            throw HanaBackupError.invalidArchive(error.localizedDescription)
        }
    }

    private static func iso8601String(from date: Date) -> String {
        let interval = date.timeIntervalSince1970
        var wholeSeconds = floor(interval)
        var nanoseconds = Int(((interval - wholeSeconds) * 1_000_000_000).rounded())
        if nanoseconds == 1_000_000_000 {
            wholeSeconds += 1
            nanoseconds = 0
        }

        let base = iso8601Formatter().string(
            from: Date(timeIntervalSince1970: wholeSeconds)
        )
        return "\(base.dropLast()).\(String(format: "%09d", nanoseconds))Z"
    }

    private static func date(fromISO8601 value: String) -> Date? {
        let formatter = iso8601Formatter()
        guard let separator = value.lastIndex(of: ".") else {
            return formatter.date(from: value)
        }

        let fractionStart = value.index(after: separator)
        guard
            let zoneStart = value[fractionStart...].firstIndex(where: {
                "Z+-".contains($0)
            })
        else {
            return nil
        }
        let fractionText = value[fractionStart..<zoneStart]
        guard !fractionText.isEmpty,
              fractionText.allSatisfy(\.isNumber),
              let fraction = Double("0.\(fractionText)") else {
            return nil
        }

        let wholeSecondsText = String(value[..<separator]) + String(value[zoneStart...])
        guard let wholeSecondsDate = formatter.date(from: wholeSecondsText) else {
            return nil
        }
        return wholeSecondsDate.addingTimeInterval(fraction)
    }

    private static func iso8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

nonisolated private struct HanaBackupHeader: Decodable {
    let schemaVersion: Int
}

nonisolated struct HanaBackupSettings: Codable, Equatable, Sendable {
    var siteBaseURL: String
    var appearanceMode: String
    var themeColor: String
    var demoModeEnabled: Bool
    var defaultVideoQuality: String
    var allowResumePlayback: Bool
    var showPlayedIndicator: Bool
    var videoLanguage: String
    var pictureInPictureEnabled: Bool
    var loopPlaybackEnabled: Bool
    var playerLongPressRate: Double
    var hKeyframesEnabled: Bool
    var hKeyframeCountdownSeconds: Int
    var hKeyframeShowPrompt: Bool
    var sharedHKeyframesEnabled: Bool
    var sharedHKeyframesPreferred: Bool
    var defaultDownloadQuality: String
    var downloadConcurrency: Int
    var warnBeforeMobileDataDownload: Bool
    var autoCheckForUpdates: Bool
    var updateLinkDestination: String
    var disciplineModeConfiguration: DisciplineModeConfiguration?
}

nonisolated struct HanaBackupWatchHistory: Codable, Equatable, Sendable {
    var videoCode: String
    var title: String
    var coverURLString: String?
    var releaseDate: Date?
    var watchDate: Date
    var progress: TimeInterval
    var duration: TimeInterval?
    var watchedAt: Date?
}

nonisolated struct HanaBackupSearchHistory: Codable, Equatable, Sendable {
    var query: String
    var createdAt: Date
}

nonisolated struct HanaBackupAdvancedSearchHistory: Codable, Equatable, Sendable {
    var criteriaKey: String
    var summary: String
    var criteriaJSON: String
    var createdAt: Date
}

nonisolated struct HanaBackupFavorite: Codable, Equatable, Sendable {
    var videoCode: String
    var title: String
    var coverURLString: String?
    var createdAt: Date
}

nonisolated struct HanaBackupWatchLater: Codable, Equatable, Sendable {
    var videoCode: String
    var title: String
    var coverURLString: String?
    var createdAt: Date
}

nonisolated struct HanaBackupPlaylist: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var detail: String
    var coverURLString: String?
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct HanaBackupPlaylistItem: Codable, Equatable, Sendable {
    var playlistID: String
    var videoCode: String
    var title: String
    var coverURLString: String?
    var createdAt: Date

    var identity: String {
        "\(playlistID)-\(videoCode)"
    }
}

nonisolated struct HanaBackupDownload: Codable, Equatable, Sendable {
    var videoCode: String
    var title: String
    var coverURLString: String?
    var quality: String
    var downloadGroupName: String
    var createdAt: Date

    var identity: String {
        "\(videoCode)\u{1F}\(quality)"
    }
}

nonisolated struct HanaBackupDownloadGroup: Codable, Equatable, Sendable {
    var name: String
    var createdAt: Date
}

nonisolated struct HanaBackupHKeyframe: Codable, Equatable, Sendable {
    var videoCode: String
    var title: String
    var groupTitle: String?
    var episode: Int
    var author: String?
    var keyframes: [HKeyframeEntry]
    var createdAt: Date
    var updatedAt: Date
}

enum HanaBackupError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidArchive(String)
    case invalidField(String)
    case duplicateRecord(String)
    case invalidReference(String)
    case missingFileData
    case activeDownloads

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Backup version \(version) is not supported. Please update Hana and retry."
        case .invalidArchive(let detail):
            "Failed to parse backup file: \(detail)"
        case .invalidField(let field):
            "Invalid \(field) in backup."
        case .duplicateRecord(let record):
            "Duplicate record in backup: \(record)."
        case .invalidReference(let reference):
            "Invalid reference in backup: \(reference)."
        case .missingFileData:
            "Backup file contains no readable data."
        case .activeDownloads:
            "Active download in progress. Finish or cancel before restoring."
        }
    }
}

extension HanaBackupArchive {
    @MainActor
    func validated() throws -> HanaBackupArchive {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw HanaBackupError.unsupportedSchemaVersion(schemaVersion)
        }

        var archive = self
        archive.settings = try settings.validated()

        guard !appVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HanaBackupError.invalidField("App Version")
        }
        guard !buildNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HanaBackupError.invalidField("Build Number")
        }

        try validateUnique(watchHistory, label: "Watch History", identity: \HanaBackupWatchHistory.videoCode)
        try validateUnique(searchHistory, label: "Search History", identity: \HanaBackupSearchHistory.query)
        try validateUnique(
            advancedSearchHistory, label: "Search History", identity: \HanaBackupAdvancedSearchHistory.criteriaKey
        )
        try validateUnique(favorites, label: "Favorites", identity: \HanaBackupFavorite.videoCode)
        try validateUnique(watchLater, label: "Watch Later", identity: \HanaBackupWatchLater.videoCode)
        try validateUnique(playlists, label: "Playlists", identity: \HanaBackupPlaylist.id)
        try validateUnique(playlistItems, label: "Playlist Item", identity: \HanaBackupPlaylistItem.identity)
        try validateUnique(downloadQueue, label: "Downloads", identity: \HanaBackupDownload.identity)
        try validateUnique(downloadGroups, label: "Download Groups", identity: \HanaBackupDownloadGroup.name)
        try validateUnique(hKeyframes, label: "HKeyframes", identity: \HanaBackupHKeyframe.videoCode)

        for record in watchHistory {
            try validateRequired(record.videoCode, field: "History Video ID")
            try validateRequired(record.title, field: "History Title")
            guard record.progress.isFinite, record.progress >= 0 else {
                throw HanaBackupError.invalidField("Watch Progress")
            }
            if let duration = record.duration, !duration.isFinite || duration < 0 {
                throw HanaBackupError.invalidField("Duration")
            }
        }

        for record in searchHistory {
            try validateRequired(record.query, field: "Search Query")
        }

        for record in advancedSearchHistory {
            try validateRequired(record.criteriaKey, field: "Search ID")
            guard let criteria = HanimeSearchCriteria.decoded(from: record.criteriaJSON),
                criteria.historyKey == record.criteriaKey
            else {
                throw HanaBackupError.invalidField("Search Filters")
            }
        }

        for record in favorites {
            try validateRequired(record.videoCode, field: "Favorite Video ID")
            try validateRequired(record.title, field: "Favorite Title")
        }
        for record in watchLater {
            try validateRequired(record.videoCode, field: "Watch Later Video ID")
            try validateRequired(record.title, field: "Watch Later Title")
        }
        for record in playlists {
            try validateRequired(record.id, field: "Playlist ID")
            try validateRequired(record.title, field: "Playlist Title")
        }

        let playlistIDs = Set(playlists.map(\.id))
        for item in playlistItems {
            try validateRequired(item.playlistID, field: "Playlist Reference")
            try validateRequired(item.videoCode, field: "Playlist Video ID")
            try validateRequired(item.title, field: "Playlist Item Title")
            guard playlistIDs.contains(item.playlistID) else {
                throw HanaBackupError.invalidReference("Playlist \(item.playlistID)")
            }
        }

        for record in downloadQueue {
            try validateRequired(record.videoCode, field: "Download Video ID")
            try validateRequired(record.title, field: "Download Title")
            try validateRequired(record.quality, field: "Download Quality")
        }
        for group in downloadGroups {
            try validateRequired(group.name, field: "Download Group Name")
        }

        for record in hKeyframes {
            try validateRequired(record.videoCode, field: "HKeyframe Video ID")
            try validateRequired(record.title, field: "HKeyframe Title")
            guard record.episode >= 0 else {
                throw HanaBackupError.invalidField("HKeyframe Episode")
            }
            var keyframeIDs = Set<String>()
            for keyframe in record.keyframes {
                guard keyframe.positionMilliseconds >= 0 else {
                    throw HanaBackupError.invalidField("HKeyframe Timestamp")
                }
                guard keyframeIDs.insert(keyframe.id).inserted else {
                    throw HanaBackupError.duplicateRecord("HKeyframe for \(record.videoCode)")
                }
            }
        }

        return archive
    }

    @MainActor
    private func validateUnique<Item>(
        _ items: [Item],
        label: String,
        identity: KeyPath<Item, String>
    ) throws {
        var identities = Set<String>()
        for item in items {
            let value = item[keyPath: identity]
            guard identities.insert(value).inserted else {
                throw HanaBackupError.duplicateRecord("\(label) \(value)")
            }
        }
    }

    @MainActor
    private func validateRequired(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HanaBackupError.invalidField(field)
        }
    }
}

extension HanaBackupSettings {
    @MainActor
    fileprivate func validated() throws -> HanaBackupSettings {
        var settings = self

        guard let normalizedURL = HanaSiteBaseURL.normalized(siteBaseURL) else {
            throw HanaBackupError.invalidField("Site URL")
        }
        settings.siteBaseURL = normalizedURL

        guard HanaAppearanceMode(rawValue: appearanceMode) != nil else {
            throw HanaBackupError.invalidField("Appearance")
        }
        guard HanaThemeColor(rawValue: themeColor) != nil else {
            throw HanaBackupError.invalidField("Accent Color")
        }
        guard HanaVideoQualityPreference(rawValue: defaultVideoQuality) != nil else {
            throw HanaBackupError.invalidField("Default Playback Quality")
        }
        settings.videoLanguage = HanaVideoLanguagePreference.normalizedRawValue(videoLanguage)
        guard HanaVideoLanguagePreference(rawValue: settings.videoLanguage) != nil else {
            throw HanaBackupError.invalidField("Subtitle Language")
        }
        guard playerLongPressRate.isFinite, playerLongPressRate > 1, playerLongPressRate <= 4 else {
            throw HanaBackupError.invalidField("Long Press Speed")
        }
        settings.playerLongPressRate = HanaPlaybackSpeedCatalog.normalizedLongPressRate(
            playerLongPressRate)
        guard (5...30).contains(hKeyframeCountdownSeconds), hKeyframeCountdownSeconds.isMultiple(of: 5)
        else {
            throw HanaBackupError.invalidField("HKeyframe Countdown")
        }
        guard HanaVideoQualityPreference(rawValue: defaultDownloadQuality) != nil else {
            throw HanaBackupError.invalidField("Default Download Quality")
        }
        guard (1...5).contains(downloadConcurrency) else {
            throw HanaBackupError.invalidField("Download Concurrency")
        }
        guard HanaUpdateLinkDestination(rawValue: updateLinkDestination) != nil else {
            throw HanaBackupError.invalidField("Update Link Target")
        }
        if let configuration = disciplineModeConfiguration {
            try configuration.validateForBackup()
        }
        return settings
    }
}

extension DisciplineModeConfiguration {
    fileprivate func validateForBackup() throws {
        switch mode {
        case .single:
            break
        case .recurring(let configuration):
            guard configuration.isValid else {
                throw HanaBackupError.invalidField("Discipline Cycle Config")
            }
        case .weekly(let configuration):
            guard configuration.isValid else {
                throw HanaBackupError.invalidField("Discipline Weekly Config")
            }
        }
    }
}
