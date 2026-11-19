import Foundation

nonisolated enum VideoProviderError: LocalizedError, Equatable, Sendable {
    case unsupported(String)
    case notConfigured(String)
    case authenticationFailed
    case invalidResponse
    case httpStatus(Int)
    case itemNotFound
    case blockedByContentPolicy

    var errorDescription: String? {
        switch self {
        case .unsupported(let feature): "This source does not support \(feature)."
        case .notConfigured(let reason): "Source is not configured: \(reason)"
        case .authenticationFailed: "Sign-in failed. Check the server address and credentials."
        case .invalidResponse: "Invalid server response"
        case .httpStatus(let code): "Server returned HTTP \(code)"
        case .itemNotFound: "Item not found"
        case .blockedByContentPolicy: "This content is not available in Hana."
        }
    }
}

/// The contract every content source implements. All methods are async and
/// nonisolated; implementations may hop to their own isolation internally
/// (`HanimeProvider` runs on the MainActor, `JellyfinProvider` is an actor).
///
/// Providers return raw data; `ProviderRegistry` applies `ContentSafetyPolicy`
/// to everything before it reaches the UI, so a provider cannot bypass it.
nonisolated protocol VideoProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }

    func home() async throws -> [MediaSection]
    func search(_ query: SearchQuery) async throws -> SearchPage
    func details(for ref: MediaItemRef) async throws -> MediaItemDetail
    func episodes(for ref: MediaItemRef) async throws -> [MediaEpisode]
    func streams(for ref: MediaItemRef) async throws -> [StreamSource]
    func markers(for ref: MediaItemRef) async throws -> [Marker]
    func filters() async throws -> FilterSet
    func reportPlayback(_ progress: PlaybackProgress) async throws
    /// Lightweight reachability/auth check used by "Test Connection".
    func testConnection() async -> (success: Bool, message: String)
}

nonisolated extension VideoProvider {
    func home() async throws -> [MediaSection] { [] }
    func episodes(for ref: MediaItemRef) async throws -> [MediaEpisode] { [] }
    func markers(for ref: MediaItemRef) async throws -> [Marker] { [] }
    func filters() async throws -> FilterSet { .empty }
    func reportPlayback(_ progress: PlaybackProgress) async throws {}
}
