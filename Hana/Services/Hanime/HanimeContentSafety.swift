import Foundation

// Applies the non-configurable `ContentSafetyPolicy` to data parsed from the
// Hanime site. Repository methods call these so every screen (home, search,
// detail, related, series, account lists) gets filtered results.

extension HanimeInfo {
    var isBlockedByContentPolicy: Bool {
        ContentSafetyPolicy.isBlocked(title)
    }
}

extension HanimeHomePage {
    func filteredByContentPolicy() -> HanimeHomePage {
        let allowedBanner = banner.flatMap { banner in
            ContentSafetyPolicy.isBlocked(any: [banner.title, banner.description].compactMap { $0 }) ? nil : banner
        }
        return HanimeHomePage(
            banner: allowedBanner,
            sections: sections.compactMap { section in
                let videos = section.videos.filter { !$0.isBlockedByContentPolicy }
                return videos.isEmpty ? nil : HanimeHomeSection(key: section.key, title: section.title, videos: videos)
            }
        )
    }
}

extension HanimeAccountVideoList {
    func filteredByContentPolicy() -> HanimeAccountVideoList {
        HanimeAccountVideoList(
            videos: videos.filter { !$0.isBlockedByContentPolicy },
            description: description,
            csrfToken: csrfToken,
            maxPage: maxPage
        )
    }
}

extension HanimeVideo {
    var isBlockedByContentPolicy: Bool {
        ContentSafetyPolicy.isBlocked(any: [title, chineseTitle].compactMap { $0 } + tags)
    }

    func filteringRelatedByContentPolicy() -> HanimeVideo {
        HanimeVideo(
            videoCode: videoCode,
            title: title,
            coverURL: coverURL,
            chineseTitle: chineseTitle,
            introduction: introduction,
            uploadTime: uploadTime,
            views: views,
            tags: tags,
            resolutions: resolutions,
            relatedVideos: relatedVideos.filter { !$0.isBlockedByContentPolicy },
            series: series.map { series in
                HanimeVideoSeries(
                    title: series.title,
                    videos: series.videos.filter { !ContentSafetyPolicy.isBlocked($0.title) }
                )
            },
            originalComicURL: originalComicURL,
            favoriteCount: favoriteCount,
            isFavorite: isFavorite,
            csrfToken: csrfToken,
            currentUserID: currentUserID,
            artist: artist,
            listState: listState
        )
    }
}
