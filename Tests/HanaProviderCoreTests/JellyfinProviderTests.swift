import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import HanaProviderCore

@Suite("Jellyfin provider against a stubbed server")
struct JellyfinProviderTests {
    func makeConfiguration(auth: ProviderAuthMethod, username: String? = "alice") -> ProviderSourceConfiguration {
        ProviderSourceConfiguration(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Home",
            kind: .jellyfin,
            baseURL: "https://media.example.com/jellyfin",
            authMethod: auth,
            username: username
        )
    }

    @Test("API key: resolves user, searches, sends MediaBrowser token header")
    func apiKeySearch() async throws {
        let configuration = makeConfiguration(auth: .apiKey, username: "Alice")
        let secrets = InMemorySecretStore()
        try secrets.setString("key-123", for: configuration.secretAccount(.apiKey))
        let transport = StubTransport()
        transport.on("GET", "/jellyfin/Users", body: try Fixture.data("jellyfin-users"))
        transport.on("GET", "/jellyfin/Items", body: try Fixture.data("jellyfin-search"))

        let provider = try JellyfinProvider(configuration: configuration, secrets: secrets, transport: transport, deviceID: "dev-1")
        let page = try await provider.search(SearchQuery(text: "planet", filters: ["genres": ["Documentary"]], pageSize: 3))

        #expect(page.items.count == 3) // raw provider output; the registry filters
        #expect(page.totalCount == 42)
        #expect(page.hasMore)

        let search = try #require(transport.recordedRequests.last)
        let components = try #require(URLComponents(url: search.url!, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["userId"] == "u-1234")
        #expect(query["searchTerm"] == "planet")
        #expect(query["genres"] == "Documentary")
        #expect(search.value(forHTTPHeaderField: "Authorization")?.contains(#"Token="key-123""#) == true)
        #expect(search.url?.query?.contains("key-123") == false)
    }

    @Test("password: signs in once, stores token in the secret store, retries on 401")
    func passwordSignIn() async throws {
        let configuration = makeConfiguration(auth: .password)
        let secrets = InMemorySecretStore()
        try secrets.setString("pw", for: configuration.secretAccount(.password))
        let transport = StubTransport()
        transport.on("POST", "/jellyfin/Users/AuthenticateByName", body: try Fixture.data("jellyfin-auth"))
        transport.on("GET", "/jellyfin/Users/Me", status: 401, body: Data())
        transport.on("GET", "/jellyfin/Items/a1b2c3d4e5f60718293a4b5c6d7e8f90", body: try Fixture.data("jellyfin-item-movie"))

        let provider = try JellyfinProvider(configuration: configuration, secrets: secrets, transport: transport, deviceID: "dev-1")
        let markers = try await provider.markers(for: MediaItemRef(providerID: configuration.providerID, itemID: "a1b2c3d4e5f60718293a4b5c6d7e8f90"))

        #expect(markers.count == 3)
        #expect(try secrets.string(for: configuration.secretAccount(.accessToken)) == "token-abc")
        let signIn = try #require(transport.recordedRequests.first { $0.url?.path.hasSuffix("AuthenticateByName") == true })
        let body = try JSONSerialization.jsonObject(with: signIn.httpBody ?? Data()) as? [String: String]
        #expect(body?["Username"] == "alice")
        #expect(body?["Pw"] == "pw")
    }

    @Test("streams: direct mp4 plus HLS fallback, auth in headers not URL")
    func streams() async throws {
        let configuration = makeConfiguration(auth: .apiKey)
        let secrets = InMemorySecretStore()
        try secrets.setString("key-123", for: configuration.secretAccount(.apiKey))
        let transport = StubTransport()
        transport.on("GET", "/jellyfin/Users", body: try Fixture.data("jellyfin-users"))
        transport.on("GET", "/jellyfin/Items/a1b2c3d4e5f60718293a4b5c6d7e8f90", body: try Fixture.data("jellyfin-item-movie"))

        let provider = try JellyfinProvider(configuration: configuration, secrets: secrets, transport: transport, deviceID: "dev-1")
        let streams = try await provider.streams(for: MediaItemRef(providerID: configuration.providerID, itemID: "a1b2c3d4e5f60718293a4b5c6d7e8f90"))

        #expect(streams.map(\.kind) == [.progressive, .hls])
        #expect(streams[0].url.path == "/jellyfin/Videos/a1b2c3d4e5f60718293a4b5c6d7e8f90/stream")
        #expect(streams[1].url.path.hasSuffix("/master.m3u8"))
        #expect(streams.allSatisfy { $0.headers["Authorization"]?.contains("key-123") == true })
        #expect(streams.allSatisfy { !($0.url.query ?? "").contains("key-123") })
    }

    @Test("rejects non-http server URLs")
    func invalidURL() {
        var configuration = makeConfiguration(auth: .apiKey)
        configuration.baseURL = "ftp://nope"
        #expect(throws: VideoProviderError.self) {
            _ = try JellyfinProvider(configuration: configuration, secrets: InMemorySecretStore(), deviceID: "d")
        }
    }
}
