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
    @Environment(HanaSiteProfileManager.self) private var siteProfiles
    @Environment(\.hanaReloadServices) private var reloadServices
    @Query(sort: \WatchHistoryRecord.watchDate, order: .reverse) private var watchHistory: [WatchHistoryRecord]
    @Query(sort: \DownloadQueueRecord.createdAt, order: .reverse) private var downloadQueue: [DownloadQueueRecord]
    @Query(sort: \HKeyframeRecord.updatedAt, order: .reverse) private var hKeyframeRecords: [HKeyframeRecord]
    @AppStorage(HanaSettingsKey.privateMode) private var privateMode = false
    @State private var accountSummaryState: ProfileAccountSummaryState = .idle
    @State private var editingProfile: SiteProfile?
    @State private var isProfileEditorPresented = false

    var body: some View {
        content
            .navigationTitle("Profile")
            .task(id: accountSummaryTaskID) {
                await loadAccountSummary()
            }
            .sheet(isPresented: $isProfileEditorPresented) {
                SiteProfileEditorSheet(profile: $editingProfile, manager: siteProfiles)
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
            Section("Site Profiles") {
                ForEach(siteProfiles.profiles) { profile in
                    Button {
                        activate(profile)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(profile.displayName).font(.headline)
                                Text(profile.baseURL).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if siteProfiles.activeProfileID == profile.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Edit") { editingProfile = profile; isProfileEditorPresented = true }
                        if siteProfiles.profiles.count > 1 {
                            Button("Delete", role: .destructive) { siteProfiles.delete(profile) }
                        }
                    }
                }
                .onMove(perform: siteProfiles.move)

                Button("Add Profile", systemImage: "plus") {
                    editingProfile = SiteProfile(id: UUID(), displayName: "", baseURL: "", loginType: .cookieSync, sourceID: nil, enabled: true, loginState: .loggedOut, lastCookieSyncAt: nil, error: nil)
                    isProfileEditorPresented = true
                }
            }

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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Site Profiles").font(.headline)
                    ForEach(siteProfiles.profiles) { profile in
                        HStack {
                            Button(profile.displayName) { activate(profile) }
                            Text(profile.baseURL).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if siteProfiles.activeProfileID == profile.id { Image(systemName: "checkmark.circle.fill") }
                            Button("Edit") { editingProfile = profile; isProfileEditorPresented = true }
                            if siteProfiles.profiles.count > 1 {
                                Button("Delete", role: .destructive) { siteProfiles.delete(profile) }
                            }
                        }
                    }
                    Button("Add Profile", systemImage: "plus") {
                        editingProfile = SiteProfile(id: UUID(), displayName: "", baseURL: "", loginType: .cookieSync, sourceID: nil, enabled: true, loginState: .loggedOut, lastCookieSyncAt: nil, error: nil)
                        isProfileEditorPresented = true
                    }
                }

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

    private func activate(_ profile: SiteProfile) {
        guard let baseURL = HanaSiteBaseURL.normalized(profile.baseURL),
              let url = URL(string: baseURL) else { return }
        siteProfiles.activate(profile)
        reloadServices(url)
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

private struct SiteProfileEditorSheet: View {
    @Binding var profile: SiteProfile?
    let manager: HanaSiteProfileManager
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SiteProfile

    init(profile: Binding<SiteProfile?>, manager: HanaSiteProfileManager) {
        _profile = profile
        self.manager = manager
        _draft = State(initialValue: profile.wrappedValue ?? SiteProfile(id: UUID(), displayName: "", baseURL: "", loginType: .cookieSync, sourceID: nil, enabled: true, loginState: .loggedOut, lastCookieSyncAt: nil, error: nil))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Display Name", text: $draft.displayName)
                TextField("Base URL", text: $draft.baseURL).textInputAutocapitalization(.never).keyboardType(.URL)
                Picker("Login Type", selection: $draft.loginType) {
                    ForEach(HanaLoginType.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Enabled", isOn: $draft.enabled)
            }
            .navigationTitle(profile == nil ? "Add Profile" : "Edit Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let normalized = HanaSiteBaseURL.normalized(draft.baseURL),
                              !draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        draft.baseURL = normalized
                        if manager.profiles.contains(where: { $0.id == draft.id }) { manager.update(draft) } else { manager.add(draft) }
                        profile = draft
                        dismiss()
                    }.disabled(draft.displayName.isEmpty || draft.baseURL.isEmpty)
                }
            }
        }
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
