import SwiftUI

struct SourcesSettingsScreen: View {
    @State private var manager = HanaSourceManager()
    @State private var editingSource: HanaSource?
    @State private var lookupText = ""
    @State private var lookupResult: HanaSourceSearchResult?
    @State private var testMessage = ""
    @State private var showingEditor = false

    var body: some View {
        Form {
            Section("Sources") {
                ForEach(manager.sources) { source in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.name).font(.headline)
                            Text("\(source.type.rawValue) ? \(source.baseURL)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let connected = source.isConnected {
                                Label(connected ? "Connected" : "Disconnected", systemImage: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption).foregroundStyle(connected ? .green : .red)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { source.enabled }, set: { value in
                            var updated = source; updated.enabled = value; manager.update(updated)
                        })).labelsHidden()
                        Button("Edit") { editingSource = source; showingEditor = true }
                            .buttonStyle(.borderless)
                    }
                }
                .onDelete(perform: manager.delete)
                .onMove(perform: manager.move)

                Button("Add Source", systemImage: "plus") {
                    editingSource = HanaSource(id: UUID(), name: "", baseURL: "", type: .hanime, enabled: true,
                                              searchEndpoint: "/search", browseEndpoint: "/", lastTestAt: nil, isConnected: nil)
                    showingEditor = true
                }
            }

            Section("Lookup") {
                TextField("Paste a video URL or ID", text: $lookupText)
                    .textInputAutocapitalization(.never)
                Button("Resolve URL") {
                    Task { lookupResult = await manager.resolveLookup(lookupText) }
                }
                if let lookupResult {
                    LabeledContent("Source", value: lookupResult.sourceName)
                    if let detailURL = lookupResult.detailURL {
                        Link("Open \(detailURL.host() ?? lookupResult.title)", destination: detailURL)
                    }
                }
            }

            Section("Built-in H@H") {
                HentaiAtHomeSettingsView(manager: manager)
            }

            Section("Privacy") {
                Toggle("Biometric Lock", isOn: .init(get: { UserDefaults.standard.bool(forKey: HanaSettingsKey.biometricLockEnabled) }, set: { UserDefaults.standard.set($0, forKey: HanaSettingsKey.biometricLockEnabled) }))
                Toggle("Private Mode", isOn: .init(get: { UserDefaults.standard.bool(forKey: HanaSettingsKey.privateMode) }, set: { UserDefaults.standard.set($0, forKey: HanaSettingsKey.privateMode) }))
                Toggle("Blur Thumbnails and Titles", isOn: .init(get: { UserDefaults.standard.bool(forKey: HanaSettingsKey.blurThumbnails) }, set: { UserDefaults.standard.set($0, forKey: HanaSettingsKey.blurThumbnails) }))
                Toggle("Hide Watched Items", isOn: .init(get: { UserDefaults.standard.bool(forKey: HanaSettingsKey.hideWatchedItems) }, set: { UserDefaults.standard.set($0, forKey: HanaSettingsKey.hideWatchedItems) }))
                Toggle("Auto-Delete Watched Downloads", isOn: .init(get: { UserDefaults.standard.bool(forKey: HanaSettingsKey.autoDeleteWatchedDownloads) }, set: { UserDefaults.standard.set($0, forKey: HanaSettingsKey.autoDeleteWatchedDownloads) }))
                SecureField("Lock Settings PIN", text: .init(get: { HanaKeychain.read(account: "hana.lockSettingsPin") ?? "" }, set: { HanaKeychain.save($0, account: "hana.lockSettingsPin") }))
                    .textContentType(.password)
            }

            Section("Playback & Picture-in-Picture") {
                Toggle("Picture-in-Picture", isOn: .init(get: { UserDefaults.standard.object(forKey: HanaSettingsKey.pictureInPictureEnabled) as? Bool ?? true }, set: { UserDefaults.standard.set($0, forKey: HanaSettingsKey.pictureInPictureEnabled) }))
                Toggle("Auto Picture-in-Picture", isOn: .init(get: { UserDefaults.standard.bool(forKey: "hana.autoPiP") }, set: { UserDefaults.standard.set($0, forKey: "hana.autoPiP") }))
                Toggle("Wi-Fi Only Thumbnail Preloading", isOn: .init(get: { UserDefaults.standard.bool(forKey: "hana.thumbnailWifiOnly") }, set: { UserDefaults.standard.set($0, forKey: "hana.thumbnailWifiOnly") }))
            }

            Section("Connection Test") {
                Text(testMessage.isEmpty ? "Select a source and use Test Connection." : testMessage)
            }
        }
        .navigationTitle("Sources")
        .sheet(isPresented: $showingEditor) {
            SourceEditorSheet(source: Binding(get: { editingSource ?? HanaSource(id: UUID(), name: "", baseURL: "", type: .hanime, enabled: true, searchEndpoint: "/search", browseEndpoint: "/", lastTestAt: nil, isConnected: nil) }, set: { editingSource = $0 }), manager: manager, testMessage: $testMessage)
        }
    }
}

private struct SourceEditorSheet: View {
    @Binding var source: HanaSource
    let manager: HanaSourceManager
    @Binding var testMessage: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $source.name)
                TextField("Base URL", text: $source.baseURL).textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Picker("Source Type", selection: $source.type) {
                    ForEach(HanaSourceType.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Search Endpoint", text: $source.searchEndpoint)
                TextField("Browse Endpoint", text: $source.browseEndpoint)
                Toggle("Enabled", isOn: $source.enabled)
                Button("Test Connection") {
                    Task {
                        let result = await manager.testConnection(source)
                        testMessage = result.1
                    }
                }
                Text(testMessage)
            }
            .navigationTitle(source.id == UUID() ? "Add Source" : "Edit Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let normalized = HanaSiteBaseURL.normalized(source.baseURL), URL(string: normalized)?.host != nil,
                              !source.name.trimmingCharacters(in: .whitespaces).isEmpty else {
                            testMessage = "Enter a name and valid URL."; return
                        }
                        source.baseURL = normalized
                        if manager.sources.contains(where: { $0.id == source.id }) { manager.update(source) } else { manager.add(source) }
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct HentaiAtHomeSettingsView: View {
    let manager: HanaSourceManager
    @State private var clientID = HanaKeychain.read(account: "hana.hh.clientID") ?? ""
    @State private var host = HanaKeychain.read(account: "hana.hh.host") ?? ""
    @State private var port = HanaKeychain.read(account: "hana.hh.port") ?? "443"
    @State private var ehUsername = HanaKeychain.read(account: "hana.hh.ehUsername") ?? ""
    @State private var exCookies = HanaKeychain.read(account: "hana.hh.exCookies") ?? ""
    @State private var status = "Disconnected"

    var body: some View {
        TextField("Client ID", text: $clientID)
        TextField("Host", text: $host).textInputAutocapitalization(.never)
        TextField("Port", text: $port).keyboardType(.numberPad)
        TextField("E-Hentai Username", text: $ehUsername)
        SecureField("ExHentai Login / Cookie", text: $exCookies)
        Button("Test H@H Connection") {
            HanaKeychain.save(clientID, account: "hana.hh.clientID")
            HanaKeychain.save(host, account: "hana.hh.host")
            HanaKeychain.save(port, account: "hana.hh.port")
            HanaKeychain.save(ehUsername, account: "hana.hh.ehUsername")
            HanaKeychain.save(exCookies, account: "hana.hh.exCookies")
            Task { await test() }
        }
        Text(status).foregroundStyle(status == "Connected" ? .green : .secondary)
    }

    private func test() async {
        guard let portNumber = UInt16(port), let url = URL(string: "https://\(host):\(portNumber)/") else {
            status = "Invalid H@H host or port"; return
        }
        var request = URLRequest(url: url); request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                status = (200..<500).contains(statusCode) ? "Connected" : "Disconnected (HTTP \(statusCode))"
            } else {
                status = "Disconnected"
            }
            UserDefaults.standard.set(Date(), forKey: "hana.hh.lastCheck")
        } catch { status = "Disconnected: \(error.localizedDescription)" }
    }
}
