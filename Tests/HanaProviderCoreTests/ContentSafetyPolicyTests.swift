import Foundation
import Testing
@testable import HanaProviderCore

@Suite("Content safety blocklist")
struct ContentSafetyPolicyTests {
    @Test("blocks minor-related terms in English, Japanese and Chinese", arguments: [
        "Shota", "loli", "Lolicon", "Gothic Lolita", "正太", "萝莉", "蘿莉", "ロリ", "ショタ",
        "JK", "jk制服", "ＪＫ", "School Swimsuit", "死庫水", "underage", "女子高生", "未成年", "小學生",
        "Teen", "school girl", "Kids",
    ])
    func blocksTerms(_ text: String) {
        #expect(ContentSafetyPolicy.isBlocked(text))
    }

    @Test("does not block unrelated adult-only terms", arguments: [
        "Office Lady", "Netorare", "Childhood Friend", "Kidnapping", "Documentary", "4K", "Jkt48x", "Teacher",
    ])
    func allowsUnrelated(_ text: String) {
        #expect(!ContentSafetyPolicy.isBlocked(text))
    }

    @Test("FilterSet can never contain blocked options")
    func filterSetStripsBlockedOptions() {
        let set = FilterSet(groups: [
            FilterGroup(id: "tags", title: "Tags", selection: .multiple, options: [
                FilterOption(title: "Shota", value: "正太"),
                FilterOption(title: "Office Lady", value: "OL"),
                FilterOption(title: "School Swimsuit", value: "死庫水"),
            ]),
            FilterGroup(id: "only-blocked", title: "Only blocked", selection: .single, options: [
                FilterOption(title: "JK", value: "JK"),
            ]),
        ])
        #expect(set.groups.count == 1)
        #expect(set.groups[0].options.map(\.value) == ["OL"])
    }

    @Test("search queries drop blocked filters and flag blocked text")
    func sanitizedQuery() {
        let query = SearchQuery(text: "loli", filters: ["tags": ["JK", "OL"]])
        let (sanitized, blocked) = query.sanitized
        #expect(blocked)
        #expect(sanitized.filters["tags"] == ["OL"])

        let clean = SearchQuery(text: "nature", filters: ["tags": ["正太"]]).sanitized
        #expect(!clean.isBlocked)
        #expect(clean.query.filters.isEmpty)
    }

    @Test("items are blocked by title, subtitle or any tag")
    func summaryBlocking() {
        let ref = MediaItemRef.legacyHanime(videoCode: "1")
        #expect(ContentSafetyPolicy.isBlocked(MediaItemSummary(ref: ref, title: "Fine", tags: ["OL", "Shota"])))
        #expect(!ContentSafetyPolicy.isBlocked(MediaItemSummary(ref: ref, title: "Fine", tags: ["OL"])))
    }
}

/// Checks the app's shipped tag catalog against the policy, so a future
/// `tags.json` update can't silently reintroduce minor-coded tags.
@Suite("Shipped tag catalog")
struct ShippedTagCatalogTests {
    private struct Entry: Decodable {
        let name: String?
        let search_key: String?
        let lang: [String: String]?
        var texts: [String] { [name, search_key].compactMap { $0 } + (lang.map { Array($0.values) } ?? []) }
    }

    private func entries() throws -> [Entry] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Hana/Resources/SearchOptions/tags.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: [Entry]].self, from: data).values.flatMap { $0 }
    }

    @Test("removed tags are gone from tags.json")
    func removedTagsAbsent() throws {
        let english = Set(try entries().compactMap { $0.lang?["en"] })
        for tag in ["Shota", "JK", "School Swimsuit", "Gothic Lolita"] {
            #expect(!english.contains(tag), "\(tag) should be removed")
        }
    }

    @Test("ordinary tags used by the app's tests stay allowed")
    func ordinaryTagsAllowed() throws {
        let all = try entries()
        for key in ["丸子頭", "福瑞", "同人作品", "背後位", "顏面騎乘"] {
            let entry = all.first { $0.search_key == key }
            #expect(entry != nil, "missing \(key)")
            #expect(!ContentSafetyPolicy.isBlocked(any: entry?.texts ?? []), "\(key) should be allowed")
        }
    }

    @Test("report entries the runtime filter still hides")
    func runtimeFilteredEntries() throws {
        let hidden = try entries().filter { ContentSafetyPolicy.isBlocked(any: $0.texts) }
        // Kept in the JSON for diffability with upstream, hidden at load time.
        print("tags.json entries hidden by policy:", hidden.compactMap { $0.lang?["en"] ?? $0.name })
    }
}
