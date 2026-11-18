import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

struct SettingsScreen: View {
    @AppStorage(HanaSettingsKey.appearanceMode) private var appearanceMode = HanaAppearanceMode.system.rawValue
#if !os(macOS)
    @AppStorage(HanaSettingsKey.themeColor) private var themeColor = HanaThemeColor.defaultValue
#endif

    var body: some View {
        themedContent
    }

    @ViewBuilder
    private var themedContent: some View {
#if os(macOS)
        macThemedContent
#else
        mobileThemedContent
#endif
    }

#if os(macOS)
    @ViewBuilder
    private var macThemedContent: some View {
        let baseContent = content
            .tint(appThemeColor)
            .accentColor(appThemeColor)

        baseContent
            .onAppear {
                applyMacOSAppearance(appAppearanceMode)
            }
            .onChange(of: appAppearanceMode) { _, mode in
                applyMacOSAppearance(mode)
            }
    }

    private func applyMacOSAppearance(_ mode: HanaAppearanceMode) {
        mode.applyToApplication()
    }
#else
    @ViewBuilder
    private var mobileThemedContent: some View {
        let baseContent = content
            .tint(appThemeColor)
            .accentColor(appThemeColor)

        if let colorScheme = appAppearanceMode.colorScheme {
            baseContent.preferredColorScheme(colorScheme)
        } else {
            baseContent
        }
    }
#endif

    @ViewBuilder
    private var content: some View {
#if os(macOS)
        MacSettingsScreen()
#else
        MobileSettingsScreen()
#endif
    }

    private var appAppearanceMode: HanaAppearanceMode {
        HanaAppearanceMode(rawValue: appearanceMode) ?? .system
    }

    private var appThemeColor: Color {
#if os(macOS)
        .pink
#else
        (HanaThemeColor(rawValue: themeColor) ?? .pink).color
#endif
    }
}

private struct MobileSettingsScreen: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    PlaybackSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .playback)
                }
                NavigationLink {
                    HKeyframeSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .hKeyframes)
                }
                NavigationLink {
                    DownloadSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .downloads)
                }
                NavigationLink {
                    AppearanceSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .appearance)
                }
                NavigationLink {
                    NetworkSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .network)
                }
                NavigationLink {
                    LocalDataSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .localData)
                }
                NavigationLink {
                    AboutSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .about)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#if os(macOS)
private struct MacSettingsScreen: View {
    @State private var selection = MacSettingsCategory.general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    settingsSidebarItem(.general)
                    settingsSidebarItem(.playback)
                }

                Section {
                    settingsSidebarItem(.hKeyframes)
                    settingsSidebarItem(.downloads)
                    settingsSidebarItem(.network)
                    settingsSidebarItem(.localData)
                }

                Section {
                    settingsSidebarItem(.about)
                }
            }
            .frame(minWidth: 180)
            .tint(appThemeColor)
            .accentColor(appThemeColor)
        } detail: {
            NavigationStack {
                settingsDetail(for: selection)
                    .formStyle(.grouped)
            }
            .tint(appThemeColor)
            .accentColor(appThemeColor)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 600)
        .tint(appThemeColor)
        .accentColor(appThemeColor)
    }

    private var appThemeColor: Color {
        .pink
    }

    private func settingsSidebarItem(_ category: MacSettingsCategory) -> some View {
        Label(category.title, systemImage: category.systemImage)
            .tag(category)
            .labelStyle(MacSettingsSidebarLabelStyle(tint: category.tint, iconSize: category.iconSize))
    }

    @ViewBuilder
    private func settingsDetail(for category: MacSettingsCategory) -> some View {
        switch category {
        case .general:
            MacGeneralSettingsScreen()
        case .playback:
            PlaybackSettingsScreen()
        case .hKeyframes:
            HKeyframeSettingsScreen()
        case .downloads:
            DownloadSettingsScreen()
        case .network:
            NetworkSettingsScreen()
        case .localData:
            LocalDataSettingsScreen()
        case .about:
            AboutSettingsScreen()
        }
    }
}

private enum MacSettingsCategory: String, CaseIterable, Identifiable {
    case general
    case playback
    case hKeyframes
    case downloads
    case network
    case localData
    case about

    var id: String { rawValue }

    var title: String {
        settingsCategory.title
    }

    var systemImage: String {
        settingsCategory.systemImage
    }

    var tint: Color {
        settingsCategory.tint
    }

    var iconSize: CGFloat {
        switch self {
        case .playback:
            12
        case .about:
            13
        case .general, .hKeyframes, .downloads, .network, .localData:
            14
        }
    }

    private var settingsCategory: SettingsCategory {
        switch self {
        case .general:
            .general
        case .playback:
            .playback
        case .hKeyframes:
            .hKeyframes
        case .downloads:
            .downloads
        case .network:
            .network
        case .localData:
            .localData
        case .about:
            .about
        }
    }
}

private struct MacSettingsSidebarLabelStyle: LabelStyle {
    let tint: Color
    let iconSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            configuration.title
        }
    }
}

private struct MacGeneralSettingsScreen: View {
    @AppStorage(HanaSettingsKey.appearanceMode) private var appearanceMode = HanaAppearanceMode.system.rawValue
    @AppStorage(HanaSettingsKey.themeColor) private var themeColor = HanaThemeColor.defaultValue
    @AppStorage(HanaSettingsKey.demoModeEnabled) private var demoModeEnabled = false
    @AppStorage(HanaSettingsKey.biometricLockEnabled) private var biometricLockEnabled = false

    var body: some View {
        Form {
            Section("Appearance") {
                MacSettingsOptionPicker(
                    title: "Theme",
                    options: HanaAppearanceMode.allCases,
                    selection: appearanceModeBinding,
                    animateSelection: false
                ) { mode, isSelected in
                    MacAppearanceModePreview(mode: mode, isSelected: isSelected)
                } label: { mode, _ in
                    mode.title
                }

                MacSettingsOptionPicker(
                    title: "Colors",
                    options: HanaThemeColor.allCases.map(\.rawValue),
                    selection: $themeColor
                ) { rawValue, isSelected in
                    MacThemeColorPreview(theme: themeColorOption(for: rawValue), isSelected: isSelected)
                } label: { rawValue, isSelected in
                    isSelected ? themeColorOption(for: rawValue).title : nil
                }
                .disabled(true)
                .grayscale(1)
                .opacity(0.45)
                .accessibilityHint("macOS version fixed to pink")

                Toggle(isOn: $demoModeEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Demo Mode")
                        Text("Blurs video covers for privacy")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear {
            resetMacOSThemeColorIfNeeded()
        }
        .onChange(of: themeColor) {
            resetMacOSThemeColorIfNeeded()
        }
    }

    private var appearanceModeBinding: Binding<HanaAppearanceMode> {
        Binding {
            HanaAppearanceMode(rawValue: appearanceMode) ?? .system
        } set: { mode in
            appearanceMode = mode.rawValue
            mode.applyToApplication()
        }
    }

    private func themeColorOption(for rawValue: String) -> HanaThemeColor {
        HanaThemeColor(rawValue: rawValue) ?? .pink
    }

    private func resetMacOSThemeColorIfNeeded() {
        guard themeColor != HanaThemeColor.defaultValue else { return }
        themeColor = HanaThemeColor.defaultValue
    }
}

private struct MacSettingsOptionPicker<Option: Hashable, Content: View>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let animateSelection: Bool
    let content: (Option, Bool) -> Content
    let label: (Option, Bool) -> String?

    init(
        title: String,
        options: [Option],
        selection: Binding<Option>,
        animateSelection: Bool = true,
        @ViewBuilder content: @escaping (Option, Bool) -> Content,
        label: @escaping (Option, Bool) -> String?
    ) {
        self.title = title
        self.options = options
        _selection = selection
        self.animateSelection = animateSelection
        self.content = content
        self.label = label
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 20)

            HStack(alignment: .top, spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection == option
                    let labelText = label(option, isSelected)

                    Button {
                        updateSelection(option)
                    } label: {
                        VStack(spacing: 4) {
                            content(option, isSelected)

                            Text(labelText ?? "")
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .frame(minHeight: 16)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(labelText ?? "")
                    .accessibilityValue(isSelected ? "Selected" : "Not Selected")
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func updateSelection(_ option: Option) {
        if animateSelection {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = option
            }
        } else {
            selection = option
        }
    }
}

private struct MacAppearanceModePreview: View {
    let mode: HanaAppearanceMode
    let isSelected: Bool

    var body: some View {
        ZStack {
            previewBackground
                .frame(width: 100, height: 64)

            HStack(spacing: 5) {
                previewPane(width: 30, color: sidebarColor)
                previewPane(width: 48, color: contentColor)
            }

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? selectionTint : Color.clear, lineWidth: 3)
        }
        .frame(width: 100, height: 64)
    }

    @ViewBuilder
    private var previewBackground: some View {
        switch mode {
        case .system:
            MacDiagonalAppearancePreviewShape()
                .fill(Color.white)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.8))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .light:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
        case .dark:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.8))
        }
    }

    @ViewBuilder
    private func previewPane(width: CGFloat, color: Color) -> some View {
        switch mode {
        case .system:
            MacDiagonalAppearancePreviewShape()
                .fill(Color.gray.opacity(0.18))
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .frame(width: width, height: 46)
        case .light, .dark:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color)
                .frame(width: width, height: 46)
        }
    }

    private var sidebarColor: Color {
        switch mode {
        case .system:
            Color.clear
        case .light:
            Color.gray.opacity(0.18)
        case .dark:
            Color.white.opacity(0.14)
        }
    }

    private var contentColor: Color {
        switch mode {
        case .system:
            Color.primary.opacity(0.12)
        case .light:
            Color.gray.opacity(0.08)
        case .dark:
            Color.white.opacity(0.08)
        }
    }

    private var selectionTint: Color {
        .pink
    }
}

private struct MacDiagonalAppearancePreviewShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MacThemeColorPreview: View {
    let theme: HanaThemeColor
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(theme.color)
            .frame(width: 24, height: 24)
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .overlay {
                Circle()
                    .strokeBorder(isSelected ? selectionTint : Color.clear, lineWidth: 3)
                    .padding(-3)
            }
            .frame(width: 34, height: 34)
    }

    private var selectionTint: Color {
        .pink
    }
}

#endif

private struct AboutSettingsScreen: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.openURL) private var openURL
    @AppStorage(HanaSettingsKey.autoCheckForUpdates) private var autoCheckForUpdates = true
    @AppStorage(HanaSettingsKey.updateLinkDestination) private var updateLinkDestination = HanaUpdateLinkDestination.defaultValue
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?
    @State private var availableUpdate: HanaAvailableUpdate?

    var body: some View {
        Form {
            Section {
                SettingsAppFooter()
                    .contentShape(Rectangle())
                    .onLongPressGesture {
                        let displayVersion = SettingsAppFooter.displayVersionText
                        guard !displayVersion.isEmpty else { return }
                        HanaPasteboard.string = displayVersion
                        toastMessage = .info("Version Copied")
                    }
            }

            Section {
                Toggle(isOn: $autoCheckForUpdates) {
                    Label("Auto Check", systemImage: "arrow.triangle.2.circlepath")
                }

#if os(iOS)
                Picker(selection: $updateLinkDestination) {
                    ForEach(HanaUpdateLinkDestination.allCases) { destination in
                        Text(destination.title).tag(destination.rawValue)
                    }
                } label: {
                    Label("Open With", systemImage: "arrow.up.forward.app")
                }
#endif

                Button {
                    Task { await checkForUpdates() }
                } label: {
                    if services.updateChecker.isChecking {
                        Label("Checking...", systemImage: "hourglass")
                    } else {
                        Label("Check for Updates", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(services.updateChecker.isChecking)
            } header: {
                Text("Updates")
            } footer: {
                Text(updateFooterText)
            }

            Section("Project") {
                Button {
                    openURL(HanaUpdateChecker.websiteURL)
                } label: {
                    Label("Project Website", systemImage: "safari")
                }

                Button {
                    openURL(HanaUpdateChecker.repositoryURL)
                } label: {
                    Label("GitHub Repo", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Button {
                    openURL(HanaUpdateChecker.releasesURL)
                } label: {
                    Label("Releases Page", systemImage: "tag")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .hanaUpdateAlert(update: $availableUpdate)
    }

    private var updateFooterText: String {
#if os(iOS)
        "Check daily for updates. Redirects to sideload app when available."
#else
        "When enabled, the app checks daily for updates."
#endif
    }

    private func checkForUpdates() async {
        do {
            let result = try await services.updateChecker.checkManually()
            switch result {
            case .updateAvailable(let update):
                availableUpdate = update
            case .upToDate:
                toastMessage = .success("Up to Date")
            case .noRelease:
                alertMessage = HanaAlertMessage(title: "No Releases", message: "No official Release found on GitHub.")
            }
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }
}

private struct SettingsNavigationRow: View {
    let category: SettingsCategory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(category.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .foregroundStyle(.primary)
                Text(category.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private enum SettingsCategory {
    case general
    case playback
    case hKeyframes
    case downloads
    case appearance
    case network
    case localData
    case about

    var title: String {
        switch self {
        case .general:
            "General"
        case .playback:
            "Play"
        case .hKeyframes:
            "HKeyframes"
        case .downloads:
            "Download"
        case .appearance:
            "Appearance"
        case .network:
            "Network & Site"
        case .localData:
            "Local Data"
        case .about:
            "About"
        }
    }

    var description: String {
        switch self {
        case .general:
            "Theme, colors, and demo mode"
        case .playback:
            "Quality, subtitles, gestures & history"
        case .hKeyframes:
            "Alerts, shared keyframes & local library"
        case .downloads:
            "Quality, concurrency, warnings & folders"
        case .appearance:
            "Follow system, or lock light/dark mode"
        case .network:
            "Site URLs, proxy, speed test & auth"
        case .localData:
            "View counts & delete locally saved data"
        case .about:
            "Version, update checks & project links"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .playback:
            "play.rectangle"
        case .hKeyframes:
            "bookmark"
        case .downloads:
            "arrow.down.circle"
        case .appearance:
            "circle.lefthalf.filled"
        case .network:
            "network"
        case .localData:
            "internaldrive"
        case .about:
            "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general:
            .red
        case .playback:
            .blue
        case .hKeyframes:
            .purple
        case .downloads:
            .green
        case .appearance:
            .pink
        case .network:
            .orange
        case .localData:
            .brown
        case .about:
            .gray
        }
    }
}

private struct PlaybackSettingsScreen: View {
    @AppStorage(HanaSettingsKey.defaultVideoQuality) private var defaultVideoQuality = HanaVideoQualityPreference.defaultValue.rawValue
    @AppStorage(HanaSettingsKey.allowResumePlayback) private var allowResumePlayback = true
    @AppStorage(HanaSettingsKey.showPlayedIndicator) private var showPlayedIndicator = true
    @AppStorage(HanaSettingsKey.videoLanguage) private var videoLanguage = HanaVideoLanguagePreference.zhHans.rawValue
    @AppStorage(HanaSettingsKey.pictureInPictureEnabled) private var pictureInPictureEnabled = true
    @AppStorage(HanaSettingsKey.loopPlaybackEnabled) private var loopPlaybackEnabled = false
    @AppStorage(HanaSettingsKey.playerLongPressRate) private var playerLongPressRate = HanaPlaybackSpeedCatalog.defaultLongPressRate

    var body: some View {
        Form {
            Section("Player") {
                Picker(selection: defaultVideoQualityBinding) {
                    ForEach(HanaVideoQualityPreference.allCases) { quality in
                        Text(quality.title).tag(quality.rawValue)
                    }
                } label: {
                    Label("Default Quality", systemImage: "slider.horizontal.3")
                }
                Picker(selection: $videoLanguage) {
                    ForEach(HanaVideoLanguagePreference.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                } label: {
                    Label("Subtitle Language", systemImage: "captions.bubble")
                }
                Toggle(isOn: $pictureInPictureEnabled) {
                    Label("Picture in Picture", systemImage: "pip")
                }
                Toggle(isOn: $loopPlaybackEnabled) {
                    Label("Loop Playback", systemImage: "repeat")
                }
            }

            Section("Gestures") {
                Picker(selection: longPressRateBinding) {
                    ForEach(HanaPlaybackSpeedCatalog.longPressRates, id: \.self) { rate in
                        Text(HanaPlaybackSpeedCatalog.title(for: rate)).tag(rate)
                    }
                } label: {
                    Label("Long Press Speed", systemImage: "forward")
                }
            }

            Section("History & Progress") {
                Toggle(isOn: $allowResumePlayback) {
                    Label("Resume Playback Progress", systemImage: "clock.arrow.circlepath")
                }
                Toggle(isOn: $showPlayedIndicator) {
                    Label("Show Watched Badge", systemImage: "checkmark.circle")
                }
            }
        }
        .navigationTitle("Play")
        .onAppear {
            videoLanguage = HanaVideoLanguagePreference.normalizedRawValue(videoLanguage)
        }
    }

    private var longPressRateBinding: Binding<Double> {
        Binding {
            HanaPlaybackSpeedCatalog.normalizedLongPressRate(playerLongPressRate)
        } set: { newValue in
            playerLongPressRate = newValue
        }
    }

    private var defaultVideoQualityBinding: Binding<String> {
        Binding {
            HanaVideoQualityPreference.normalizedRawValue(defaultVideoQuality)
        } set: { newValue in
            defaultVideoQuality = newValue
        }
    }
}

private struct DownloadSettingsScreen: View {
    @Environment(HanaServices.self) private var services
    @AppStorage(HanaSettingsKey.defaultDownloadQuality) private var defaultDownloadQuality = HanaVideoQualityPreference.defaultValue.rawValue
    @AppStorage(HanaSettingsKey.downloadConcurrency) private var downloadConcurrency = 2
    @AppStorage(HanaSettingsKey.startDownloadsImmediately) private var startDownloadsImmediately = true
    @AppStorage(HanaSettingsKey.warnBeforeMobileDataDownload) private var warnBeforeMobileDataDownload = true
    @State private var downloadDirectoryName = HanaDownloadDirectoryPreference.displayName()
    @State private var isDirectoryImporterPresented = false
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?

    var body: some View {
        Form {
            Section("Tasks") {
                Picker(selection: defaultDownloadQualityBinding) {
                    ForEach(HanaVideoQualityPreference.allCases) { quality in
                        Text(quality.title).tag(quality.rawValue)
                    }
                } label: {
                    Label("Download Preference", systemImage: "arrow.down.circle")
                }
                Stepper(value: $downloadConcurrency, in: 1...5) {
                    LabeledContent {
                        Text("\(downloadConcurrency)")
                    } label: {
                        Label("Concurrent Downloads", systemImage: "number")
                    }
                }
                Toggle(isOn: $startDownloadsImmediately) {
                    Label("Download Immediately When Added", systemImage: "bolt.fill")
                }
            }

            Section("Network") {
                Toggle(isOn: $warnBeforeMobileDataDownload) {
                    Label("Warn Before Cellular Download", systemImage: "antenna.radiowaves.left.and.right")
                }
            }

            Section("Directory") {
                LabeledContent {
                    Text(downloadDirectoryName)
                } label: {
                    Label("Location", systemImage: "folder")
                }

                Button {
                    isDirectoryImporterPresented = true
                } label: {
                    Label("Select External Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    exportDownloadsToExternalDirectory()
                } label: {
                    Label("Export to External Folder", systemImage: "square.and.arrow.up")
                }
                .disabled(!HanaDownloadDirectoryPreference.hasExternalDirectoryBookmark())

                Button {
                    importDownloadsFromExternalDirectory()
                } label: {
                    Label("Import from External Folder", systemImage: "square.and.arrow.down")
                }
                .disabled(!HanaDownloadDirectoryPreference.hasExternalDirectoryBookmark())

                Button(role: .destructive) {
                    useApplicationDownloadDirectory()
                } label: {
                    Label("Use App Directory", systemImage: "internaldrive")
                }
            }
        }
        .navigationTitle("Download")
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .fileImporter(
            isPresented: $isDirectoryImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleDownloadDirectoryImport(result)
        }
        .onAppear {
            refreshDownloadDirectoryName()
        }
        .onChange(of: downloadConcurrency) { _, _ in
            services.downloadClient.downloadConcurrencyDidChange()
        }
    }

    private func handleDownloadDirectoryImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            guard didStartAccessing else {
                throw HanaDownloadDirectoryError.accessDenied
            }
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            try HanaDownloadDirectoryPreference.saveExternalDirectory(url)
            try services.downloadClient.refreshExternalDirectoryAccess()
            refreshDownloadDirectoryName()
            toastMessage = .success("Selected \(url.lastPathComponent)")
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }

    private func useApplicationDownloadDirectory() {
        HanaDownloadDirectoryPreference.clear()
        do {
            try services.downloadClient.refreshExternalDirectoryAccess()
            refreshDownloadDirectoryName()
            toastMessage = .success("Switched to App Directory")
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }

    private var defaultDownloadQualityBinding: Binding<String> {
        Binding {
            HanaVideoQualityPreference.normalizedRawValue(defaultDownloadQuality)
        } set: { newValue in
            defaultDownloadQuality = newValue
        }
    }

    private func exportDownloadsToExternalDirectory() {
        do {
            let count = try services.downloadClient.exportDownloadsToExternalDirectory()
            toastMessage = count > 0
                ? .success("Exported \(count) files")
                : .info("No files available to export in app directory.")
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }

    private func importDownloadsFromExternalDirectory() {
        do {
            let count = try services.downloadClient.importDownloadsFromExternalDirectory()
            toastMessage = count > 0
                ? .success("Imported \(count) files")
                : .info("No downloadable files found in external folder.")
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }

    private func refreshDownloadDirectoryName() {
        do {
            downloadDirectoryName = try HanaDownloadDirectoryPreference.resolvedExternalDirectory()?.lastPathComponent ?? "App Directory"
        } catch {
            downloadDirectoryName = "Reselection Required"
            alertMessage = .error(error.localizedDescription)
        }
    }
}

private struct AppearanceSettingsScreen: View {
    @AppStorage(HanaSettingsKey.appearanceMode) private var appearanceMode = HanaAppearanceMode.system.rawValue
    @AppStorage(HanaSettingsKey.themeColor) private var themeColor = HanaThemeColor.defaultValue
    @AppStorage(HanaSettingsKey.demoModeEnabled) private var demoModeEnabled = false

    var body: some View {
        Form {
            Picker(selection: $appearanceMode) {
                ForEach(HanaAppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode.rawValue)
                }
            } label: {
                Text("Theme")
            }
            .pickerStyle(.inline)

            Picker(selection: $themeColor) {
                ForEach(HanaThemeColor.allCases) { theme in
                    ThemeColorOptionLabel(theme: theme)
                        .tag(theme.rawValue)
                }
            } label: {
                Text("Accent Color")
            }
            .pickerStyle(.inline)

            Section {
                Toggle("Demo Mode", isOn: $demoModeEnabled)
            } footer: {
                Text("Blur video cover thumbnails")
            }

            Section {
                Toggle("Face ID / Passcode Lock", isOn: $biometricLockEnabled)
            } header: {
                Text("Security")
            } footer: {
                Text("Require biometric authentication to unlock Hana on launch and when switching apps.")
            }
        }
        .navigationTitle("Appearance")
    }
}

private struct ThemeColorOptionLabel: View {
    let theme: HanaThemeColor

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(theme.color)
                .frame(width: 16, height: 16)
                .overlay {
                    Circle()
                        .stroke(.secondary.opacity(0.25), lineWidth: 1)
                }
            Text(theme.title)
        }
    }
}

private struct NetworkSettingsScreen: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.hanaReloadServices) private var reloadServices
    @AppStorage(HanaSettingsKey.siteBaseURL) private var storedSiteBaseURL = HanaSiteBaseURL.defaultValue
    @AppStorage(HanaSettingsKey.networkProxyMode) private var proxyMode = HanaNetworkProxyMode.system.rawValue
    @AppStorage(HanaSettingsKey.networkProxyHost) private var proxyHost = ""
    @AppStorage(HanaSettingsKey.networkProxyPort) private var proxyPort = 7890
    @State private var selectedBaseURL = HanaSiteBaseURL.defaultValue
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?
    @State private var latencyResults: [SiteLatencyResult] = []
    @State private var isTestingLatency = false
    @State private var isApplyingNetworkSettings = false
    @State private var isCredentialLoginPresented = false

    var body: some View {
        Form {
            Section("Site") {
                LabeledContent {
                    Text(services.httpClient.baseURL.absoluteString)
                } label: {
                    Label("Address", systemImage: "link")
                }
                LabeledContent {
                    Text("\(services.siteSession.lastSyncedCookieCount)")
                } label: {
                    Label("Cookie", systemImage: "doc.badge.gearshape")
                }
                if let date = services.siteSession.lastCookieSyncAt {
                    LabeledContent {
                        Text(date.hanaChineseDateTimeText)
                    } label: {
                        Label("Sync Time", systemImage: "clock.arrow.circlepath")
                    }
                }
                LabeledContent {
                    Text(services.siteSession.cloudflareStatusText)
                } label: {
                    Label("Cloudflare", systemImage: "shield.lefthalf.filled")
                }
                if let date = services.siteSession.lastCloudflareVerifiedAt {
                    LabeledContent {
                        Text(date.hanaChineseDateTimeText)
                    } label: {
                        Label("Auth Time", systemImage: "checkmark.shield")
                    }
                }
            }

            Section("Site URL") {
                Picker(selection: selectedBaseURLBinding) {
                    ForEach(HanaSiteBaseURL.options, id: \.self) { url in
                        Text(url).tag(url)
                    }
                    if !HanaSiteBaseURL.options.contains(selectedBaseURL) {
                        Text(selectedBaseURL).tag(selectedBaseURL)
                    }
                } label: {
                    Label("Current Selection", systemImage: "globe")
                }
            }

            Section("Proxy") {
                Picker(selection: $proxyMode) {
                    ForEach(HanaNetworkProxyMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                } label: {
                    Label("Mode", systemImage: "network")
                }

                if selectedProxyMode.requiresEndpoint {
                    LabeledContent {
                        TextField("Host", text: $proxyHost)
                            .hanaTextInputAutocapitalizationNever()
                            .hanaURLKeyboard()
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Host", systemImage: "server.rack")
                    }
                    LabeledContent {
                        TextField("Port", value: $proxyPort, format: .number)
                            .hanaNumberKeyboard()
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Port", systemImage: "number")
                    }
                }

                Button {
                    Task { await applyNetworkSettings() }
                } label: {
                    if isApplyingNetworkSettings {
                        Label("Applying...", systemImage: "hourglass")
                    } else {
                        Label("Apply Network Settings", systemImage: "network")
                    }
                }
                .disabled(isApplyingNetworkSettings)
            }

            Section("Site Speed Test") {
                Button {
                    Task { await runLatencyTests() }
                } label: {
                    if isTestingLatency {
                        Label("Testing Speed...", systemImage: "hourglass")
                    } else {
                        Label("Test Site URLs", systemImage: "speedometer")
                    }
                }
                .disabled(isTestingLatency)

                ForEach(latencyResults) { result in
                    LabeledContent {
                        Text(result.summary)
                            .foregroundStyle(result.isReachable ? Color.secondary : Color.red)
                    } label: {
                        Label(result.url.host() ?? result.url.absoluteString, systemImage: "globe")
                    }
                }
            }

            Section("Current Network") {
                LabeledContent {
                    Text(services.networkMonitor.statusTitle)
                } label: {
                    Label("Status", systemImage: "wave.3.right")
                }
                LabeledContent {
                    Text(services.networkMonitor.usesCellular ? "Yes" : "No")
                } label: {
                    Label("Cellular Network", systemImage: "antenna.radiowaves.left.and.right")
                }
                LabeledContent {
                    Text(services.networkMonitor.isExpensive ? "Yes" : "No")
                } label: {
                    Label("Metered Connection", systemImage: "gauge.with.dots.needle.67percent")
                }
            }

            Section("Verification") {
                Button {
                    services.siteSession.requestLogin()
                } label: {
                    Label("Log In", systemImage: "person.crop.circle")
                }
                Button {
                    isCredentialLoginPresented = true
                } label: {
                    Label("Account Login", systemImage: "key")
                }
                Button(role: .destructive) {
                    Task { await services.logout() }
                } label: {
                    Label("Clear Site Login State", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Network & Site")
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .sheet(isPresented: $isCredentialLoginPresented) {
            SiteCredentialLoginSheet()
        }
        .onAppear {
            selectedBaseURL = services.httpClient.baseURL.absoluteString
        }
    }

    private var selectedBaseURLBinding: Binding<String> {
        Binding(
            get: { selectedBaseURL },
            set: { newValue in
                selectedBaseURL = newValue
                applySiteBaseURL(newValue)
            }
        )
    }

    private var selectedProxyMode: HanaNetworkProxyMode {
        HanaNetworkProxyMode(rawValue: proxyMode) ?? .system
    }

    private func applyNetworkSettings() async {
        guard !services.downloadClient.hasActiveDownloads else {
            alertMessage = .error("Download in progress. Finish before applying.")
            return
        }
        guard selectedProxyMode.requiresEndpoint == false || proxyPort > 0 else {
            alertMessage = .error("Invalid proxy port")
            return
        }

        isApplyingNetworkSettings = true
        defer { isApplyingNetworkSettings = false }
        await services.siteSession.invalidateCloudflareVerification()
        reloadServices(services.httpClient.baseURL)
        toastMessage = .success("Network settings applied")
    }

    private func runLatencyTests() async {
        isTestingLatency = true
        latencyResults = []
        defer { isTestingLatency = false }

        for url in siteCandidates() {
            let result = await measureSiteLatency(url)
            latencyResults.append(result)
        }
    }

    private func siteCandidates() -> [URL] {
        let rawValues = HanaSiteBaseURL.options
        var seen = Set<String>()
        return rawValues.compactMap { value in
            guard let normalized = HanaSiteBaseURL.normalized(value),
                  seen.insert(normalized).inserted,
                  let url = URL(string: normalized) else {
                return nil
            }
            return url
        }
    }

    private func measureSiteLatency(_ url: URL) async -> SiteLatencyResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.connectionProxyDictionary = HanaNetworkProxySettings.current().connectionProxyDictionary
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(HanaHTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let startedAt = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            return SiteLatencyResult(
                url: url,
                milliseconds: milliseconds,
                status: statusCode.map { "HTTP \($0)" } ?? "Valid Response",
                isReachable: statusCode.map { (200..<500).contains($0) } ?? true
            )
        } catch {
            let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
            return SiteLatencyResult(
                url: url,
                milliseconds: milliseconds,
                status: error.localizedDescription,
                isReachable: false
            )
        }
    }

    private func applySiteBaseURL(_ value: String) {
        guard let normalized = HanaSiteBaseURL.normalized(value),
              let url = URL(string: normalized) else {
            alertMessage = .error("Invalid URL")
            return
        }
        if services.httpClient.baseURL.absoluteString == normalized {
            storedSiteBaseURL = normalized
            selectedBaseURL = normalized
            toastMessage = .info("Currently using this URL")
            return
        }
        guard !services.downloadClient.hasActiveDownloads else {
            selectedBaseURL = services.httpClient.baseURL.absoluteString
            alertMessage = .error("Download in progress. Finish before switching.")
            return
        }
        storedSiteBaseURL = normalized
        selectedBaseURL = normalized
        reloadServices(url)
        toastMessage = .success("Switched to \(url.host() ?? normalized)")
    }
}

private struct SiteLatencyResult: Identifiable, Hashable {
    var id: String { url.absoluteString }

    let url: URL
    let milliseconds: Int
    let status: String
    let isReachable: Bool

    var summary: String {
        "\(milliseconds) ms · \(status)"
    }
}

private struct LocalDataSettingsScreen: View {
    @Environment(HanaServices.self) private var services
    @Environment(DisciplineModeStore.self) private var disciplineModeStore
    @Environment(\.hanaReloadServices) private var reloadServices
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SearchHistoryRecord.createdAt, order: .reverse) private var searchHistory: [SearchHistoryRecord]
    @Query(sort: \AdvancedSearchHistoryRecord.createdAt, order: .reverse) private var advancedSearchHistory: [AdvancedSearchHistoryRecord]
    @Query(sort: \WatchHistoryRecord.watchDate, order: .reverse) private var watchHistory: [WatchHistoryRecord]
    @Query(sort: \DownloadQueueRecord.createdAt, order: .reverse) private var downloadQueue: [DownloadQueueRecord]
    @Query(sort: \HKeyframeRecord.updatedAt, order: .reverse) private var hKeyframeRecords: [HKeyframeRecord]
    @State private var pendingDeletion: LocalDataDeletionTarget?
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?
    @State private var exportDocument: HanaBackupDocument?
    @State private var isExporterPresented = false
    @State private var isImporterPresented = false
    @State private var isProcessingBackup = false

    var body: some View {
        Form {
            Section("Backup & Restore") {
                Button {
                    prepareBackupExport()
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
                .disabled(isProcessingBackup)

                Button {
                    isImporterPresented = true
                } label: {
                    Label("Restore Backup", systemImage: "square.and.arrow.down")
                }
                .disabled(isProcessingBackup)

                if isProcessingBackup {
                    HStack {
                        ProgressView()
                        Text("Processing...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Record Counts") {
                LabeledContent {
                    Text("\(watchHistory.count)")
                } label: {
                    Label("Watch History", systemImage: "clock.arrow.circlepath")
                }
                LabeledContent {
                    Text("\(searchHistory.count)")
                } label: {
                    Label("Search History", systemImage: "magnifyingglass")
                }
                LabeledContent {
                    Text("\(advancedSearchHistory.count)")
                } label: {
                    Label("Search History", systemImage: "line.3.horizontal.decrease.circle")
                }
                LabeledContent {
                    Text("\(downloadQueue.count)")
                } label: {
                    Label("Download Queue", systemImage: "arrow.down.circle")
                }
                LabeledContent {
                    Text("\(hKeyframeRecords.count)")
                } label: {
                    Label("HKeyframes", systemImage: "bookmark")
                }
            }

            Section("Data Management") {
                LocalDataDeletionButton(
                    title: "Delete Watch History",
                    systemImage: "clock.arrow.circlepath",
                    count: watchHistory.count,
                    target: .watchHistory,
                    pendingDeletion: $pendingDeletion
                )
                LocalDataDeletionButton(
                    title: "Delete Search History",
                    systemImage: "magnifyingglass",
                    count: searchHistory.count + advancedSearchHistory.count,
                    target: .searchHistory,
                    pendingDeletion: $pendingDeletion
                )
                LocalDataDeletionButton(
                    title: "Delete Downloads & Files",
                    systemImage: "arrow.down.circle",
                    count: downloadQueue.count,
                    target: .downloads,
                    pendingDeletion: $pendingDeletion
                )
                LocalDataDeletionButton(
                    title: "Delete Keyframes",
                    systemImage: "bookmark",
                    count: hKeyframeRecords.count,
                    target: .hKeyframes,
                    pendingDeletion: $pendingDeletion
                )
                LocalDataDeletionButton(
                    title: "Delete All Local Data",
                    systemImage: "trash",
                    count: totalRecordCount,
                    target: .all,
                    pendingDeletion: $pendingDeletion
                )
            }

        }
        .navigationTitle("Local Data")
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .hanaBackup,
            defaultFilename: backupFilename
        ) { result in
            handleBackupExport(result)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: HanaBackupDocument.readableContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleBackupImport(result)
        }
        .confirmationDialog(
            pendingDeletion?.confirmationTitle ?? "Delete Data",
            isPresented: deletionDialogBinding,
            titleVisibility: .visible
        ) {
            if let pendingDeletion {
                Button(pendingDeletion.actionTitle, role: .destructive) {
                    delete(pendingDeletion)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            if let pendingDeletion {
                Text(pendingDeletion.confirmationMessage)
            }
        }
    }

    private var totalRecordCount: Int {
        watchHistory.count
            + searchHistory.count
            + advancedSearchHistory.count
            + downloadQueue.count
            + hKeyframeRecords.count
    }

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Hana-Backup-\(formatter.string(from: .now)).hanabackup"
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding {
            pendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                pendingDeletion = nil
            }
        }
    }

    private func delete(_ target: LocalDataDeletionTarget) {
        var downloadDeletionError: Error?
        do {
            switch target {
            case .watchHistory:
                watchHistory.forEach(modelContext.delete)
            case .searchHistory:
                searchHistory.forEach(modelContext.delete)
                advancedSearchHistory.forEach(modelContext.delete)
            case .downloads:
                downloadDeletionError = deleteDownloads()
            case .hKeyframes:
                hKeyframeRecords.forEach(modelContext.delete)
            case .all:
                downloadDeletionError = deleteDownloads()
                watchHistory.forEach(modelContext.delete)
                searchHistory.forEach(modelContext.delete)
                advancedSearchHistory.forEach(modelContext.delete)
                hKeyframeRecords.forEach(modelContext.delete)
            }
            try modelContext.save()
            pendingDeletion = nil
            if let downloadDeletionError {
                let prefix = target == .all ? "Other data deleted; " : ""
                let message =
                    "\(prefix)Some download files could not be deleted; records retained:"
                    + downloadDeletionError.localizedDescription
                alertMessage = .error(message)
            } else {
                toastMessage = .success("\(target.title) deleted")
            }
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }

    private func prepareBackupExport() {
        isProcessingBackup = true
        Task {
            defer { isProcessingBackup = false }
            do {
                let archive = try HanaBackupService.makeArchive(modelContext: modelContext)
                let data = try await HanaBackupCodec.shared.encode(archive)
                exportDocument = HanaBackupDocument(data: data)
                isExporterPresented = true
            } catch is CancellationError {
                return
            } catch {
                alertMessage = .error(error.localizedDescription)
            }
        }
    }

    private func handleBackupExport(_ result: Result<URL, Error>) {
        exportDocument = nil
        switch result {
        case .success:
            toastMessage = .success("Backup exported")
        case .failure(let error) where isUserCancellation(error):
            break
        case .failure(let error):
            alertMessage = .error(error.localizedDescription)
        }
    }

    private func handleBackupImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error) where isUserCancellation(error):
            return
        case .failure(let error):
            alertMessage = .error(error.localizedDescription)
            return
        case .success(let urls):
            guard let url = urls.first else { return }
            restoreBackup(from: url)
        }
    }

    private func restoreBackup(from url: URL) {
        isProcessingBackup = true
        Task {
            defer { isProcessingBackup = false }
            do {
                guard !services.downloadClient.hasActiveDownloads else {
                    throw HanaBackupError.activeDownloads
                }
                let previousBaseURL = services.httpClient.baseURL
                let archive = try await HanaBackupCodec.shared.readArchive(from: url)
                let summary = try HanaBackupService.importArchive(
                    archive,
                    modelContext: modelContext
                )
                let records = try modelContext.fetch(FetchDescriptor<DownloadQueueRecord>())
                await HanaDownloadRecordSynchronizer.synchronize(
                    downloadClient: services.downloadClient,
                    modelContext: modelContext,
                    records: records
                )
                disciplineModeStore.reload()
                if let normalizedBaseURL = HanaSiteBaseURL.normalized(archive.settings.siteBaseURL),
                   let restoredBaseURL = URL(string: normalizedBaseURL),
                   restoredBaseURL != previousBaseURL {
                    reloadServices(restoredBaseURL)
                }
                toastMessage = .success(summary.message)
            } catch is CancellationError {
                return
            } catch {
                alertMessage = .error(error.localizedDescription)
            }
        }
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    private func deleteDownloads() -> Error? {
        var firstError: Error?
        for item in downloadQueue {
            services.downloadClient.cancel(id: item.id)
            if let localFileURLString = item.localFileURLString,
               let url = URL(string: localFileURLString) {
                do {
                    try services.downloadClient.deleteLocalDownload(fileURL: url)
                } catch {
                    firstError = firstError ?? error
                    continue
                }
            }
            modelContext.delete(item)
        }
        return firstError
    }
}

private enum LocalDataDeletionTarget: Identifiable, Equatable {
    case watchHistory
    case searchHistory
    case downloads
    case hKeyframes
    case all

    var id: String { title }

    var title: String {
        switch self {
        case .watchHistory:
            "Watch History"
        case .searchHistory:
            "Search History"
        case .downloads:
            "Downloads & Files"
        case .hKeyframes:
            "HKeyframes"
        case .all:
            "All Local Data"
        }
    }

    var confirmationTitle: String {
        "Confirm Delete \(title)"
    }

    var confirmationMessage: String {
        switch self {
        case .downloads:
            "Deletes download records and local files."
        case .hKeyframes:
            "Deletes locally saved HKeyframes."
        case .all:
            "Deletes history, downloads, keyframes & video files."
        default:
            "This operation only affects local device data."
        }
    }

    var actionTitle: String {
        "Delete \(title)"
    }
}

private struct LocalDataDeletionButton: View {
    let title: String
    let systemImage: String
    let count: Int
    let target: LocalDataDeletionTarget
    @Binding var pendingDeletion: LocalDataDeletionTarget?

    var body: some View {
        Button(role: .destructive) {
            pendingDeletion = target
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(count == 0)
    }
}
