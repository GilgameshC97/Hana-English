import Foundation
import Testing
@testable import HanaProviderCore

@Suite("Jellyfin response decoding")
struct JellyfinDecodingTests {
    let providerID = ProviderID(kind: .jellyfin, sourceID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
    let baseURL = URL(string: "https://media.example.com/jellyfin/")!

    @Test("search result decodes and maps to summaries")
    func searchResult() throws {
        let result = try JSONDecoder().decode(JellyfinQueryResult.self, from: Fixture.data("jellyfin-search"))
        #expect(result.items.count == 3)
        #expect(result.totalRecordCount == 42)

        let movie = JellyfinProvider.summary(for: result.items[0], providerID: providerID, baseURL: baseURL)
        #expect(movie.title == "Planet Documentary")
        #expect(movie.kind == .movie)
        #expect(movie.durationSeconds == 3600)
        #expect(movie.resumePositionSeconds == 600)
        #expect(movie.subtitle == "2019")
        #expect(movie.ref == MediaItemRef(providerID: providerID, itemID: "a1b2c3d4e5f60718293a4b5c6d7e8f90"))
        #expect(movie.coverURL?.absoluteString == "https://media.example.com/jellyfin/Items/a1b2c3d4e5f60718293a4b5c6d7e8f90/Images/Primary?maxWidth=600&quality=90&tag=img001")

        let episode = JellyfinProvider.summary(for: result.items[1], providerID: providerID, baseURL: baseURL)
        #expect(episode.kind == .episode)
        #expect(episode.subtitle == "Space Show · S1E1")
        #expect(episode.isPlayed)
        #expect(episode.resumePositionSeconds == nil)
        #expect(episode.coverURL?.path == "/jellyfin/Items/11112222333344445555666677778888/Images/Primary")
    }

    @Test("item with chapters maps to markers in milliseconds")
    func chaptersToMarkers() throws {
        let item = try JSONDecoder().decode(JellyfinItem.self, from: Fixture.data("jellyfin-item-movie"))
        let markers = JellyfinProvider.markers(from: item)
        #expect(markers.map(\.positionMilliseconds) == [0, 900_000, 2_700_000])
        #expect(markers.map(\.title) == ["Opening", "Oceans", "Credits"])
        #expect(markers.allSatisfy { $0.source == .provider })
        #expect(item.mediaSources?.first?.supportsDirectStream == true)
        #expect(JellyfinDate.parse(item.premiereDate) != nil)
    }

    @Test("auth, users, filters and system info decode")
    func otherPayloads() throws {
        let auth = try JSONDecoder().decode(JellyfinAuthenticationResult.self, from: Fixture.data("jellyfin-auth"))
        #expect(auth.accessToken == "token-abc")
        #expect(auth.user?.id == "u-1234")

        let users = try JSONDecoder().decode([JellyfinUser].self, from: Fixture.data("jellyfin-users"))
        #expect(users.count == 3)
        #expect(users[2].policy?.isDisabled == true)

        let filters = try JSONDecoder().decode(JellyfinQueryFilters.self, from: Fixture.data("jellyfin-filters"))
        #expect(filters.years == [2019, 2021])

        let info = try JSONDecoder().decode(JellyfinPublicSystemInfo.self, from: Fixture.data("jellyfin-system-info"))
        #expect(info.serverName == "Home Server")
    }

    @Test("ticks convert both ways")
    func ticks() {
        #expect(JellyfinTicks.seconds(36_000_000_000) == 3600)
        #expect(JellyfinTicks.seconds(0) == nil)
        #expect(JellyfinTicks.ticks(seconds: 1.5) == 15_000_000)
    }

    @Test("authorization header uses the MediaBrowser scheme")
    func authorizationHeader() {
        let header = JellyfinProvider.authorizationHeader(client: "Hana", device: "iPhone", deviceID: "dev-1", version: "1.0", token: "abc")
        #expect(header == #"MediaBrowser Client="Hana", Device="iPhone", DeviceId="dev-1", Version="1.0", Token="abc""#)
    }
}
