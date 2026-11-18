import SwiftData
import SwiftUI

private enum ProfileAccountSummaryState: Equatable {
    case idle
    case loading
    case loaded(watchLaterCount: Int, playlistCount: Int)
    case unavailable
    case failed
}

struct ProfileScreen: View {
    @Environment(HanaServices.self) private var services
    @Query(sort: \WatchHistoryRecord.watchDate, order: .reverse) private var watchHistory: [WatchHistoryRecord]
    @Query(sort: \DownloadQueueRecord.createdAt, order: .reverse) private var downloadQueue: [DownloadQueueRecord]
    @Query(sort: \HKeyframeRecord.updatedAt, order: .reverse) private var hKeyframeRecords: [HKeyframeRecord]
    @AppStorage(HanaSettingsKey.privateMode) private var privateMode = false
    @State private var accountSummaryState: ProfileAccountSummaryState = .idle

    var body: some View {
        content
            .navigationTitle("Profile")
            .task(id: accountSummaryTaskID) {
                await loadAccountSummary()
            }
    }

    @ViewBuilder
    private var content: some View {
#if os(macOS)
        macOSContent
#else
        mobileContent
#endif
    }

    private var mobileContent: some View {
        List {
            Section {
                profileHeaderLink
            }

            Section {
                NavigationLink(value: HanaRoute.watchHistory) {
                    ProfileNavigationRow(
                        title: "Watch History",
                        value: "\(visibleWatchHistoryCount)",
                        systemImage: "clock.arrow.circlepath"
                    )
                }

                NavigationLink(value: HanaRoute.watchLater) {
                    ProfileNavigationRow(
                        title: "Watch Later",
                        value: watchLaterValue,
                        systemImage: "text.badge.plus"
                    )
                }

                NavigationLink(value: HanaRoute.playlists) {
                    ProfileNavigationRow(
                        title: "Playlists",
                        value: playlistValue,
                        systemImage: "list.bullet.rectangle"
                    )
                }

                NavigationLink(value: HanaRoute.hKeyframes) {
                    ProfileNavigationRow(
                        title: "HKeyframes",
                        value: "\(hKeyframeRecords.count)",
                        systemImage: "bookmark"
                    )
                }

                NavigationLink(value: HanaRoute.downloads) {
                    ProfileNavigationRow(
                        title: "Downloaded Videos",
                        value: "\(downloadQueue.count)",
                        systemImage: "arrow.down.circle"
                    )
                }
            }

            Section {
                NavigationLink(value: HanaRoute.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }

#if os(macOS)
    private var macOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                profileHeaderLink
                    .buttonStyle(.plain)

                Divider()

                Form {
                    MacOSProfileNavigationLink(
                        route: .watchHistory,
                        title: "Watch History",
                        value: "\(visibleWatchHistoryCount)",
                        systemImage: "clock.arrow.circlepath"
                    )

                    MacOSProfileNavigationLink(
                        route: .watchLater,
                        title: "Watch Later",
                        value: watchLaterValue,
                        systemImage: "text.badge.plus"
                    )

                    MacOSProfileNavigationLink(
                        route: .playlists,
                        title: "Playlists",
                        value: playlistValue,
                        systemImage: "list.bullet.rectangle"
                    )

                    MacOSProfileNavigationLink(
                        route: .hKeyframes,
                        title: "HKeyframes",
                        value: "\(hKeyframeRecords.count)",
                        systemImage: "bookmark"
                    )

                    MacOSProfileNavigationLink(
                        route: .downloads,
                        title: "Downloaded Videos",
                        value: "\(downloadQueue.count)",
                        systemImage: "arrow.down.circle"
                    )
                }
                .formStyle(.grouped)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollContentBackground(.visible)
    }
#endif

    private var profileHeaderLink: some View {
        NavigationLink(value: HanaRoute.profileDetail) {
            ProfileAccountHeader(
                displayName: services.siteSession.isLoggedIn ? services.siteSession.displayName : "Not Logged In",
                accountStatusIcon: accountStatusIcon,
                accountStatusText: accountStatusText,
                siteText: services.siteSession.baseURL.absoluteString,
                avatarURL: avatarURL
            )
            .blur(radius: privateMode ? 8 : 0)
        }
    }

    private var accountSummaryTaskID: String {
        let syncTime = services.siteSession.lastCookieSyncAt?.timeIntervalSince1970 ?? 0
        return "\(services.siteSession.isLoggedIn)-\(services.siteSession.userID ?? "")-\(syncTime)"
    }

    private var accountStatusText: String {
        if let userID = services.siteSession.userID, services.siteSession.isLoggedIn {
            return userID
        }
        return "Log in to sync subscriptions & favorites"
    }

    private var accountStatusIcon: String {
        services.siteSession.isLoggedIn ? "person.text.rectangle" : "person.crop.circle.badge.exclamationmark"
    }

    private var avatarURL: URL? {
        services.siteSession.avatarURLString.flatMap(URL.init(string:))
    }

    private var visibleWatchHistoryCount: Int {
        watchHistory.filter(\.isHistoryEligible).count
    }

    private var watchLaterValue: String {
        accountSummaryValue(\.watchLaterCount)
    }

    private var playlistValue: String {
        accountSummaryValue(\.playlistCount)
    }

    private func accountSummaryValue(_ keyPath: KeyPath<ProfileLoadedAccountSummary, Int>) -> String {
        switch accountSummaryState {
        case .loaded(let watchLaterCount, let playlistCount):
            let summary = ProfileLoadedAccountSummary(
                watchLaterCount: watchLaterCount,
                playlistCount: playlistCount
            )
            return "\(summary[keyPath: keyPath])"
        case .idle, .loading:
            return services.siteSession.isLoggedIn ? "Loading..." : "—"
        case .unavailable, .failed:
            return "—"
        }
    }

    private func loadAccountSummary() async {
        guard services.siteSession.isLoggedIn else {
            accountSummaryState = .unavailable
            return
        }
        guard let userID = services.siteSession.userID else {
            accountSummaryState = .unavailable
            return
        }

        if shouldShowInitialAccountSummaryLoading {
            accountSummaryState = .loading
        }
        do {
            let watchLaterCount = try await loadAccountVideoCount(kind: .watchLater, userID: userID)
            let playlistCount = try await loadPlaylistCount(userID: userID)
            accountSummaryState = .loaded(watchLaterCount: watchLaterCount, playlistCount: playlistCount)
        } catch is CancellationError {
            return
        } catch {
            _ = services.siteSession.handle(error)
            if shouldShowAccountSummaryFailure {
                accountSummaryState = .failed
            }
        }
    }

    private var shouldShowAccountSummaryFailure: Bool {
        switch accountSummaryState {
        case .loaded:
            false
        case .idle, .loading, .unavailable, .failed:
            true
        }
    }

    private var shouldShowInitialAccountSummaryLoading: Bool {
        switch accountSummaryState {
        case .loaded:
            false
        case .idle, .loading, .unavailable, .failed:
            true
        }
    }

    private func loadAccountVideoCount(kind: HanimeMyListKind, userID: String) async throws -> Int {
        let firstPage = try await services.repository.accountVideos(kind: kind, userID: userID, page: 1)
        guard firstPage.maxPage > 1 else { return firstPage.videos.count }

        var count = firstPage.videos.count
        for page in 2...firstPage.maxPage {
            let nextPage = try await services.repository.accountVideos(kind: kind, userID: userID, page: page)
            count += nextPage.videos.count
        }
        return count
    }

    private func loadPlaylistCount(userID: String) async throws -> Int {
        let firstPage = try await services.repository.playlists(userID: userID, page: 1)
        guard firstPage.maxPage > 1 else { return firstPage.playlists.count }

        var count = firstPage.playlists.count
        for page in 2...firstPage.maxPage {
            let nextPage = try await services.repository.playlists(userID: userID, page: page)
            count += nextPage.playlists.count
        }
        return count
    }
}

private struct ProfileLoadedAccountSummary {
    let watchLaterCount: Int
    let playlistCount: Int
}

#if os(macOS)
private struct MacOSProfileNavigationLink: View {
    let route: HanaRoute
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        NavigationLink(value: route) {
            LabeledContent {
                Text(value)
                    .foregroundStyle(.secondary)
            } label: {
                Label(title, systemImage: systemImage)
            }
        }
    }
}
#endif

private struct ProfileNavigationRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
