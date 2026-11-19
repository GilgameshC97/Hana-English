import Testing

@testable import Hana

@Suite("Search contract")
struct HanimeSearchContractTests {
    @Test("tag catalog uses current site keys and Chinese labels")
    func currentTagKeys() {
        let options = HanimeSearchOptionCatalog.tagSections.flatMap(\.options)
        let valuesByTitle = Dictionary(
            options.compactMap { option in
                option.value.map { (option.title, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        #expect(valuesByTitle["同人作品"] == "同人作品")
        #expect(valuesByTitle["Furry"] == "福瑞")
        #expect(valuesByTitle["丸子头"] == "丸子頭")
        #expect(valuesByTitle["哥特萝莉塔"] == nil) // removed by ContentSafetyPolicy
        #expect(valuesByTitle["背后位"] == "背後位")
        #expect(valuesByTitle["颜面骑乘"] == "顏面騎乘")
        #expect(valuesByTitle["雷火剑"] == nil)
    }

    @Test("detail tags and endpoints send catalog search keys")
    func tagRequestValues() {
        #expect(HanimeSearchOptionCatalog.tagSearchKey(matching: "丸子头") == "丸子頭")
        #expect(HanimeSearchOptionCatalog.tagSearchKey(matching: "Furry") == "福瑞")

        let endpoint = HanaEndpoint.search(
            criteria: HanimeSearchCriteria(tags: ["丸子頭", "福瑞"]),
            page: 3
        )
        #expect(endpoint.queryItems.first { $0.name == "page" }?.value == "3")
        #expect(
            endpoint.queryItems
                .filter { $0.name == "tags[]" }
                .compactMap(\.value) == ["丸子頭", "福瑞"]
        )
    }

    @Test("minor-coded tags never reach the catalog or the request")
    func blockedTagsAreRemoved() {
        let options = HanimeSearchOptionCatalog.tagSections.flatMap(\.options)
        let blocked = options.filter { option in
            ContentSafetyPolicy.isBlocked(any: [option.title, option.value].compactMap { $0 })
        }
        #expect(blocked.isEmpty)
        #expect(HanimeSearchOptionCatalog.tagSearchKey(matching: "正太") == nil)
        #expect(HanimeSearchOptionCatalog.tagSearchKey(matching: "JK") == nil)

        let endpoint = HanaEndpoint.search(
            criteria: HanimeSearchCriteria(tags: ["丸子頭", "正太", "JK"]),
            page: 1
        )
        #expect(
            endpoint.queryItems
                .filter { $0.name == "tags[]" }
                .compactMap(\.value) == ["丸子頭"]
        )
    }
}
