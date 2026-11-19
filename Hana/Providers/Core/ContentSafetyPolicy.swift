import Foundation

/// Hard, non-configurable content policy: anything that depicts, is tagged as,
/// or caters to minors is excluded at the model level.
///
/// There is intentionally **no** setting, flag, environment variable, backup
/// field or initializer parameter that disables this. Every provider result,
/// filter option and search query passes through it (see `FilterSet.init`,
/// `SearchQuery.sanitized`, `ProviderRegistry`, `HanimeSearchOptionCatalog`
/// and `HanimeRepository`). Matching is deliberately conservative: a few
/// legitimate titles may be hidden, which is the accepted trade-off.
nonisolated enum ContentSafetyPolicy {
    /// Terms matched as substrings after normalization (NFKC, lowercased,
    /// whitespace/punctuation removed). Covers English, Japanese, and both
    /// Simplified and Traditional Chinese spellings.
    static let blockedSubstrings: [String] = [
        // English
        "loli", "shota", "underage", "jailbait", "preteen", "pedo",
        "schoolgirl", "schoolboy", "schoolswimsuit", "elementaryschool", "middleschool", "juniorhigh",
        "highschoolgirl", "highschoolboy",
        // Japanese
        "ロリ", "ショタ", "幼女", "幼児", "児童", "小学生", "中学生", "女子高生", "女子校生", "スク水", "ランドセル",
        // Chinese (Simplified / Traditional)
        "萝莉", "蘿莉", "正太", "幼儿", "幼兒", "儿童", "兒童", "未成年", "小学", "小學", "中学生", "中學生",
        "初中", "國中", "国中", "高中生", "死库水", "死庫水", "校园", "校園", "学生妹", "學生妹",
    ]

    /// Short Latin tokens that are only blocked as whole words (so "jk" in
    /// "JK制服" is caught, but "kidnap" or "childhood" are not).
    static let blockedWords: Set<String> = [
        "jk", "jc", "js", "ds", "child", "children", "kid", "kids", "minor", "minors",
        "teen", "teens", "teenage", "teenager", "young", "school", "student", "students",
        "toddler", "infant", "baby", "babies",
    ]

    static func isBlocked(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return false }
        let compact = normalized.filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol }
        if blockedSubstrings.contains(where: { compact.contains($0) }) {
            return true
        }
        return latinWords(in: normalized).contains(where: blockedWords.contains)
    }

    static func isBlocked(any texts: [String]) -> Bool {
        texts.contains(where: { isBlocked($0) })
    }

    static func allowedTags(_ tags: [String]) -> [String] {
        tags.filter { !isBlocked($0) }
    }

    /// True if the item itself (title or any tag) is blocked.
    static func isBlocked(_ item: MediaItemSummary) -> Bool {
        isBlocked(item.title) || isBlocked(item.subtitle) || isBlocked(any: item.tags)
    }

    static func isBlocked(_ detail: MediaItemDetail) -> Bool {
        isBlocked(detail.summary)
            || isBlocked(detail.alternateTitle)
            || isBlocked(detail.overview)
            || isBlocked(detail.seriesTitle)
            || isBlocked(any: detail.tags)
    }

    static func filter(_ items: [MediaItemSummary]) -> [MediaItemSummary] {
        items.filter { !isBlocked($0) }
    }

    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
    }

    private static func latinWords(in text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}
