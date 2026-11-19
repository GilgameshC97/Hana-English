//
//  ContentView.swift
//  Hana
//
//  Created by Kanscape on 2026/5/16.
//

import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ContentView: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
#if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @AppStorage(HanaSettingsKey.biometricLockEnabled) private var isBiometricLockEnabled = false
    @ObservedObject private var biometricAuth = BiometricAuthService.shared
    @AppStorage(HanaSettingsKey.appearanceMode) private var appearanceMode = HanaAppearanceMode.system.rawValue
#if !os(macOS)
    @AppStorage(HanaSettingsKey.themeColor) private var themeColor = HanaThemeColor.defaultValue
#endif
    @Query(sort: \DownloadQueueRecord.createdAt, order: .reverse) private var downloadQueue: [DownloadQueueRecord]
    @State private var selectedTab: AppTab = .discover
#if os(macOS)
    @State private var macOSNavigationPath: [HanaRoute] = []
#else
    @State private var iOSNavigationPath: [HanaRoute] = []
    @State private var playbackLinkIDs: [String: String] = [:]
#endif

    private var appThemeColor: Color {
#if os(macOS)
        .pink
#else
        (HanaThemeColor(rawValue: themeColor) ?? .pink).color
#endif
    }

#if os(macOS)
    private var macOSSidebarProfileTitle: String {
        services.siteSession.isLoggedIn ? services.siteSession.displayName : "Not Logged In"
    }
#endif

    var body: some View {
        let content = Group {
            if isBiometricLockEnabled && !biometricAuth.isUnlocked {
                BiometricLockOverlayView {
                    biometricAuth.authenticate()
                }
            } else {
                unlockedAppContent
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if isBiometricLockEnabled && !biometricAuth.isUnlocked {
                    biometricAuth.authenticate()
                }
            } else if phase == .background {
                if isBiometricLockEnabled {
                    biometricAuth.lock()
                }
            }
        }
        .tint(appThemeColor)
        .accentColor(appThemeColor)

#if os(macOS)
        content
            .onAppear {
                applyMacOSAppearance()
            }
            .onChange(of: appearanceMode) { _, _ in
                applyMacOSAppearance()
            }
#else
        content
            .preferredColorScheme(HanaAppearanceMode(rawValue: appearanceMode)?.colorScheme)
#endif
    }

    private var unlockedAppContent: some View {
        @Bindable var siteSession = services.siteSession
        @Bindable var updateChecker = services.updateChecker

        return rootContent
            .sheet(item: $siteSession.activeFlow) { flow in
                SiteWebSessionSheet(
                    flow: flow,
                    onComplete: { cookies in
                        completeSiteWebFlow(
                            flowID: flow.id,
                            kind: flow.kind,
                            cookies: cookies
                        )
                    },
                    onCancel: {
                        services.siteSession.cancel(flowID: flow.id)
                    }
                )
            }
            .task {
                await refreshLoginStateFromStoredCookies()
                await synchronizeDownloadsAtLaunch()
                await services.updateChecker.checkAutomaticallyIfNeeded()
            }
            .hanaUpdateAlert(update: $updateChecker.availableUpdate)
    }

#if os(macOS)
    private func applyMacOSAppearance() {
        let mode = HanaAppearanceMode(rawValue: appearanceMode) ?? .system
        mode.applyToApplication()
    }
#endif

    @ViewBuilder
    private var rootContent: some View {
#if os(macOS)
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedTab) {
                    NavigationLink(value: AppTab.discover) {
                        Label("Discover", systemImage: "sparkles")
                    }
                    NavigationLink(value: AppTab.subscriptions) {
                        Label("Subscriptions", systemImage: "play.rectangle.on.rectangle")
                    }
                    NavigationLink(value: AppTab.favorites) {
                        Label("Favorites", systemImage: "heart")
                    }
                    NavigationLink(value: AppTab.search) {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                }
                .listStyle(.sidebar)

                MacOSSidebarProfileButton(
                    title: macOSSidebarProfileTitle,
                    imageData: services.profileAvatarStore.imageData,
                    isSelected: selectedTab == .profile
                ) {
                    selectedTab = .profile
                    macOSNavigationPath.removeAll()
                }
            }
            .navigationTitle("Hana")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
        } detail: {
            NavigationStack(path: $macOSNavigationPath) {
                tabContent(for: selectedTab)
                    .navigationDestination(for: HanaRoute.self, destination: destination)
            }
        }
        .hanaMacOSWindowToolbarChrome()
        .onChange(of: selectedTab) {
            macOSNavigationPath.removeAll()
        }
#else
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                List {
                    iOSSplitSidebarButton(title: "Discover", systemImage: "sparkles", tab: .discover, selectedTab: $selectedTab)
                    iOSSplitSidebarButton(title: "Subscriptions", systemImage: "play.rectangle.on.rectangle", tab: .subscriptions, selectedTab: $selectedTab)
                    iOSSplitSidebarButton(title: "Favorites", systemImage: "heart", tab: .favorites, selectedTab: $selectedTab)
                    iOSSplitSidebarButton(title: "Profile", systemImage: "person.crop.circle", tab: .profile, selectedTab: $selectedTab)
                    iOSSplitSidebarButton(title: "Search", systemImage: "magnifyingglass", tab: .search, selectedTab: $selectedTab)
                }
                .listStyle(.sidebar)
                .navigationTitle("Hana")
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            } detail: {
                NavigationStack(path: $iOSNavigationPath) {
                    tabContent(for: selectedTab)
                        .navigationDestination(for: HanaRoute.self, destination: destination)
                }
            }
            .onChange(of: selectedTab) {
                iOSNavigationPath.removeAll()
            }
        } else {
            TabView(selection: $selectedTab) {
                Tab("Discover", systemImage: "sparkles", value: AppTab.discover) {
                    NavigationStack(path: $iOSNavigationPath) {
                        HomeScreen()
                            .navigationDestination(for: HanaRoute.self, destination: destination)
                    }
                }

                Tab("Subscriptions", systemImage: "play.rectangle.on.rectangle", value: AppTab.subscriptions) {
                    NavigationStack(path: $iOSNavigationPath) {
                        SubscriptionsScreen()
                            .navigationDestination(for: HanaRoute.self, destination: destination)
                    }
                }

                Tab("Favorites", systemImage: "heart", value: AppTab.favorites) {
                    NavigationStack(path: $iOSNavigationPath) {
                        FavoritesScreen()
                            .navigationDestination(for: HanaRoute.self, destination: destination)
                    }
                }

                Tab(value: AppTab.profile) {
                    NavigationStack(path: $iOSNavigationPath) {
                        ProfileScreen()
                            .navigationDestination(for: HanaRoute.self, destination: destination)
                    }
                } label: {
                    ProfileTabLabel()
                }

                Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                    NavigationStack(path: $iOSNavigationPath) {
                        SearchScreen()
                            .navigationDestination(for: HanaRoute.self, destination: destination)
                    }
                }
            }
            .hanaTabSearchActivation()
            .onChange(of: selectedTab) {
                iOSNavigationPath.removeAll()
            }
        }
#endif
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .discover:
            HomeScreen()
        case .subscriptions:
            SubscriptionsScreen()
        case .favorites:
            FavoritesScreen()
        case .profile:
            ProfileScreen()
        case .search:
            SearchScreen()
        }
    }

    @ViewBuilder
    private func destination(_ route: HanaRoute) -> some View {
        switch route {
        case .video(let code):
#if os(macOS)
            VideoDetailScreen(videoCode: code, isNavigationTop: macOSNavigationPath.last == .video(code))
#else
            VideoDetailScreen(
                videoCode: code,
                selectedPlaybackLinkID: Binding(
                    get: { playbackLinkIDs[code] ?? "" },
                    set: { playbackLinkIDs[code] = $0 }
                )
            )
#endif
        case .search(let criteria):
            SearchScreen(initialCriteria: criteria)
        case .lockedSearch(let criteria):
            SearchScreen(initialCriteria: criteria, locksQueryEditing: true)
        case .profileDetail:
            ProfileDetailScreen()
        case .watchHistory:
            WatchHistoryScreen()
        case .watchLater:
            WatchLaterScreen()
        case .playlists:
            PlaylistsScreen()
        case .remotePlaylist(let playlist):
            RemotePlaylistDetailScreen(playlist: playlist)
        case .hKeyframes:
            HKeyframeManagementScreen()
        case .downloads:
            DownloadsScreen()
        case .settings:
            SettingsScreen()
        case .providerItem(let ref):
            ProviderItemDetailScreen(ref: ref)
        }
    }

    private func completeSiteWebFlow(
        flowID: UUID,
        kind: SiteWebFlowKind,
        cookies: [HTTPCookie]
    ) {
        guard services.siteSession.complete(flowID: flowID, with: cookies) else { return }
        if kind == .login {
            Task { await refreshLoginState() }
        }
    }

    private func refreshLoginStateFromStoredCookies() async {
        await services.siteSession.syncDefaultWebCookies()
        guard services.siteSession.hasStoredCookies || services.siteSession.isLoggedIn else {
            services.profileAvatarStore.clear()
            return
        }
        await verifyCurrentUser()
    }

    private func refreshLoginState() async {
        await services.siteSession.syncDefaultWebCookies()
        await verifyCurrentUser()
    }

    private func verifyCurrentUser() async {
        do {
            let user = try await services.repository.currentUser()
            await services.applyLoginState(user: user)
        } catch {
            if services.siteSession.handle(error)
                || services.siteSession.shouldPreserveLoginState(after: error) {
                return
            }
            await services.applyLoginState(user: nil)
        }
    }

    private func synchronizeDownloadsAtLaunch() async {
        await HanaDownloadRecordSynchronizer.synchronize(
            downloadClient: services.downloadClient,
            modelContext: modelContext,
            records: downloadQueue
        )
    }
}

#if os(macOS)
private struct MacOSSidebarProfileButton: View {
    let title: String
    let imageData: Data?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                MacOSSidebarProfileAvatar(imageData: imageData)

                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 56, alignment: .center)
            .contentShape(.rect)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .accessibilityLabel(title)
        .accessibilityHint("Open Profile")
    }
}

private struct MacOSSidebarProfileAvatar: View {
    let imageData: Data?
    private let side: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(.secondary.opacity(0.16))

            avatarContent
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.secondary.opacity(0.22), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let imageData,
           let image = NSImage(data: imageData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: side - 4))
                .foregroundStyle(.secondary)
        }
    }
}
#endif

private struct iOSSplitSidebarButton: View {
    let title: String
    let systemImage: String
    let tab: AppTab
    @Binding var selectedTab: AppTab

    var body: some View {
        Button {
            selectedTab = tab
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedTab == tab ? Color.accentColor.opacity(0.16) : Color.clear)
        )
    }
}

private struct ProfileTabLabel: View {
    @Environment(HanaServices.self) private var services

    var body: some View {
        Label {
            Text("Profile")
        } icon: {
            ProfileTabIcon(imageData: services.profileAvatarStore.imageData)
        }
    }
}

private struct ProfileTabIcon: View {
    let imageData: Data?
    private let side = HanaProfileAvatarStore.tabIconPointSize

    var body: some View {
#if canImport(UIKit)
        if let imageData,
           let image = UIImage(data: imageData, scale: HanaProfileAvatarStore.tabIconImageScale)?.withRenderingMode(.alwaysOriginal) {
            Image(uiImage: image)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: side, height: side)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .frame(width: side, height: side)
        }
#else
        Image(systemName: "person.crop.circle.fill")
            .frame(width: side, height: side)
#endif
    }
}

private enum AppTab: Hashable {
    case discover
    case subscriptions
    case favorites
    case profile
    case search
}

private extension View {
    @ViewBuilder
    func hanaMacOSWindowToolbarChrome() -> some View {
#if os(macOS)
        toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
#else
        self
#endif
    }

    @ViewBuilder
    func hanaTabSearchActivation() -> some View {
#if os(iOS) || os(macOS)
        tabViewSearchActivation(.searchTabSelection)
#else
        self
#endif
    }
}

#Preview {
    ContentView()
        .environment(HanaServices())
        .modelContainer(
            for: [
                WatchHistoryRecord.self,
                SearchHistoryRecord.self,
                AdvancedSearchHistoryRecord.self,
                FavoriteVideoRecord.self,
                WatchLaterRecord.self,
                PlaylistRecord.self,
                PlaylistItemRecord.self,
                DownloadQueueRecord.self,
                HKeyframeRecord.self,
            ],
            inMemory: true
        )
}
