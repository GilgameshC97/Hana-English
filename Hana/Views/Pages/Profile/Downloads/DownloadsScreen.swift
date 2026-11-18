import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private let defaultDownloadGroupName = "Default Group"

struct DownloadsScreen: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @AppStorage(HanaSettingsKey.warnBeforeMobileDataDownload) private var warnBeforeMobileDataDownload = true
    @Query(sort: \DownloadQueueRecord.createdAt, order: .reverse) private var queue: [DownloadQueueRecord]
    @Query(sort: \DownloadGroupRecord.name, order: .forward) private var downloadGroups: [DownloadGroupRecord]
    @Query(sort: \WatchHistoryRecord.watchDate, order: .reverse) private var watchHistory: [WatchHistoryRecord]
    @State private var localPlayback: LocalVideoPlayback?
    @State private var mobileDataDownloadID: String?
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?
    @State private var isCreateGroupPresented = false
    @State private var isGroupManagerPresented = false
    @State private var movingDownloadItem: DownloadQueueRecord?
    @State private var newGroupName = ""
    @State private var isSelectionModeActive = false
    @State private var selectedDownloadIDs = Set<String>()
    @State private var isSelectedDeleteConfirmationPresented = false
    @State private var storageText = "Calculating…"

    var body: some View {
        content
            .navigationTitle("Downloaded Videos")
            .hanaToast($toastMessage)
            .hanaFeedbackAlert($alertMessage)
            .toolbar { downloadToolbar }
            .sheet(item: $localPlayback) { playback in
                LocalVideoPlayerSheet(playback: playback)
            }
            .sheet(isPresented: $isGroupManagerPresented) {
                DownloadGroupManagementSheet(
                    groupNames: downloadGroupNames,
                    onRename: renameDownloadGroup,
                    onDelete: deleteDownloadGroup
                )
            }
            .sheet(item: $movingDownloadItem) { item in
                DownloadMoveGroupSheet(
                    item: item,
                    groupNames: downloadGroupNames,
                    onMove: moveDownloadItem
                )
            }
            .alert("New Group", isPresented: $isCreateGroupPresented) {
                TextField("Group Name", text: $newGroupName)
                Button("Create") {
                    createDownloadGroup(named: newGroupName)
                    newGroupName = ""
                }
                .disabled(normalizedDownloadGroupName(newGroupName) == defaultDownloadGroupName)
                Button("Cancel", role: .cancel) {
                    newGroupName = ""
                }
            }
            .task {
                await synchronizeDownloadRecords(showStatus: false)
                refreshStorageSize()
                await monitorDownloadSnapshots()
            }
            .alert("Metered network detected", isPresented: mobileDataAlertBinding) {
                Button("Resume Download") {
                    continueAfterMobileDataWarning()
                }
                Button("Cancel", role: .cancel) {
                    mobileDataDownloadID = nil
                }
            } message: {
                Text("Cellular download warning is enabled in Settings.")
            }
            .confirmationDialog("Delete selected downloads?", isPresented: $isSelectedDeleteConfirmationPresented, titleVisibility: .visible) {
                Button("Delete \(selectedDownloadIDs.count) Files", role: .destructive) {
                    deleteSelected()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Cancels tasks and removes downloaded local files.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if visibleDownloadQueue.isEmpty {
            ContentUnavailableView {
                Label("No downloaded videos", systemImage: "arrow.down.circle")
            } description: {
                Text("Downloaded or scanned videos will appear here.")
            } actions: {
                Button(action: scanLocalDownloads) {
                    Label("Scan Local Files", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            downloadList
        }
    }

    private var downloadList: some View {
        List {
            DownloadQueueList(
                items: queue,
                groupNames: downloadGroupNames,
                progressProvider: progress(for:),
                isDownloadingProvider: isDownloading(id:),
                onStart: startDownloadAction,
                onPause: pauseDownload,
                onResume: resumeDownload,
                onCancel: cancelDownload,
                onPlay: playLocalFile,
                onDelete: delete,
                onMoveGroup: { item in
                    movingDownloadItem = item
                },
                isEditing: isEditing,
                selectedDownloadIDs: selectedDownloadIDs,
                onToggleSelection: toggleSelection
            )
        }
    }

    @ToolbarContentBuilder
    private var downloadToolbar: some ToolbarContent {
        if !visibleDownloadQueue.isEmpty {
            ToolbarItemGroup(placement: .primaryAction) {
                if isEditing {
                    HanaToolbarIconButton(title: "Done Selecting", systemImage: "xmark", action: toggleEditMode)

                    HanaToolbarIconButton(
                        title: areAllVisibleDownloadsSelected ? "Deselect All" : "Select All",
                        systemImage: areAllVisibleDownloadsSelected ? "circle" : "checkmark.circle"
                    ) {
                        toggleAll()
                    }
                    .disabled(visibleDownloadQueue.isEmpty)

                    HanaToolbarIconButton(title: "Delete Selected (\(selectedDownloadIDs.count))", systemImage: "trash", role: .destructive) {
                        isSelectedDeleteConfirmationPresented = true
                    }
                    .disabled(selectedDownloadIDs.isEmpty)
                } else {
                    Menu {
                        Button("Pause All Active") { pauseAllDownloads() }
                        Button("Resume All Paused") { resumeAllDownloads() }
                        Divider()
                        Button("Delete Watched Downloads", role: .destructive) { deleteWatchedDownloads() }
                        Divider()
                        Label(storageText, systemImage: "internaldrive")
                    } label: {
                        Label("Download Controls", systemImage: "slider.horizontal.3")
                    }

                    Button {
                        newGroupName = ""
                        isCreateGroupPresented = true
                    } label: {
                        Label("New Group", systemImage: "folder.badge.plus")
                    }

                    Button {
                        isGroupManagerPresented = true
                    } label: {
                        Label("Manage Groups", systemImage: "folder")
                    }
                    .disabled(queue.isEmpty && downloadGroupNames.count <= 1)

                    Button(action: toggleEditMode) {
                        Label("Select", systemImage: "checklist")
                    }

                    Button(action: scanLocalDownloads) {
                        Label("Scan Local Files", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private func progress(for id: String) -> Double? {
        services.downloadClient.progress(for: id)
    }

    private func isDownloading(id: String) -> Bool {
        services.downloadClient.isDownloading(id: id)
    }

    private var isEditing: Bool {
        isSelectionModeActive
    }

    private var visibleDownloadQueue: [DownloadQueueRecord] {
        queue.filter(\.shouldAppearInDownloads)
    }

    private var areAllVisibleDownloadsSelected: Bool {
        let ids = Set(visibleDownloadQueue.map(\.id))
        return !ids.isEmpty && selectedDownloadIDs.isSuperset(of: ids)
    }

    private func toggleEditMode() {
        withAnimation(.smooth(duration: 0.2)) {
            if isSelectionModeActive {
                isSelectionModeActive = false
                selectedDownloadIDs.removeAll()
            } else {
                isSelectionModeActive = true
            }
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedDownloadIDs.contains(id) {
            selectedDownloadIDs.remove(id)
        } else {
            selectedDownloadIDs.insert(id)
        }
    }

    private func toggleAll() {
        let ids = Set(visibleDownloadQueue.map(\.id))
        if selectedDownloadIDs.isSuperset(of: ids) {
            selectedDownloadIDs.subtract(ids)
        } else {
            selectedDownloadIDs.formUnion(ids)
        }
    }

    private func startDownloadAction(_ item: DownloadQueueRecord) {
        guard !item.mediaURLString.hasPrefix("file://") else {
            alertMessage = .error("Local file has no remote download URL.")
            return
        }
        if shouldConfirmMobileDataDownload {
            mobileDataDownloadID = item.id
            return
        }
        Task { await startDownload(item) }
    }

    private func playLocalFile(item: DownloadQueueRecord, url: URL) {
        localPlayback = LocalVideoPlayback(fileURL: url, title: item.title)
    }

    private func startDownload(_ item: DownloadQueueRecord) async {
        await HanaDownloadStarter.start(
            item,
            downloadClient: services.downloadClient,
            siteSession: services.siteSession,
            modelContext: modelContext
        )
    }

    private func monitorDownloadSnapshots() async {
        while !Task.isCancelled {
            let snapshotsByID = Dictionary(
                uniqueKeysWithValues: services.downloadClient.persistedTasks().map { ($0.id, $0) }
            )
            var changed = false
            for item in queue {
                guard let snapshot = snapshotsByID[item.id] else {
                    continue
                }
                let isCurrent = item.backgroundTaskUpdatedAt == snapshot.updatedAt
                    && item.backgroundTaskIdentifier == snapshot.taskIdentifier
                    && item.progress == snapshot.progress
                    && item.localFileURLString == snapshot.localFileURLString
                    && item.completionNotificationSentAt == snapshot.notificationSentAt
                    && item.status == HanaDownloadRecordSynchronizer.downloadStatusTitle(for: snapshot)
                guard !isCurrent else {
                    continue
                }
                HanaDownloadRecordSynchronizer.apply(snapshot, to: item)
                changed = true
            }
            if changed {
                try? modelContext.save()
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func pauseDownload(_ item: DownloadQueueRecord) {
        services.downloadClient.pause(id: item.id)
        if let snapshot = services.downloadClient.persistedTask(id: item.id) {
            HanaDownloadRecordSynchronizer.apply(snapshot, to: item)
        }
        try? modelContext.save()
    }

    private func pauseAllDownloads() {
        for item in queue where services.downloadClient.isDownloading(id: item.id) {
            pauseDownload(item)
        }
        toastMessage = .success("Paused active downloads")
    }

    private func resumeAllDownloads() {
        for item in queue where services.downloadClient.persistedTask(id: item.id)?.status == .paused {
            resumeDownload(item)
        }
        toastMessage = .success("Resumed paused downloads")
    }

    private func deleteWatchedDownloads() {
        let watchedCodes = Set(watchHistory.filter(\.isWatched).map(\.videoCode))
        let items = queue.filter { watchedCodes.contains($0.videoCode) }
        guard !items.isEmpty else {
            toastMessage = .success("No watched downloads found")
            return
        }
        delete(items: items)
        toastMessage = .success("Deleted \(items.count) watched downloads")
        refreshStorageSize()
    }

    private func refreshStorageSize() {
        Task { @MainActor in
            do {
                let files = try services.downloadClient.localDownloads()
                let bytes = files.reduce(Int64(0)) { partial, file in
                    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    return partial + Int64(size)
                }
                storageText = "Storage Used: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
            } catch {
                storageText = "Storage Size Unavailable"
            }
        }
    }

    private func resumeDownload(_ item: DownloadQueueRecord) {
        services.downloadClient.resume(id: item.id)
        if let snapshot = services.downloadClient.persistedTask(id: item.id) {
            HanaDownloadRecordSynchronizer.apply(snapshot, to: item)
        }
        try? modelContext.save()
    }

    private func cancelDownload(_ item: DownloadQueueRecord) {
        services.downloadClient.cancel(id: item.id)
        if let snapshot = services.downloadClient.persistedTask(id: item.id) {
            HanaDownloadRecordSynchronizer.apply(snapshot, to: item)
        }
        try? modelContext.save()
    }

    private func delete(_ offsets: IndexSet) {
        delete(items: offsets.compactMap { index in
            queue.indices.contains(index) ? queue[index] : nil
        })
    }

    private func deleteSelected() {
        let selectedItems = queue.filter { selectedDownloadIDs.contains($0.id) }
        delete(items: selectedItems)
        selectedDownloadIDs.removeAll()
        isSelectionModeActive = false
    }

    private func delete(items: [DownloadQueueRecord]) {
        var firstError: Error?
        for item in items {
            do {
                try services.downloadClient.remove(id: item.id)
            } catch {
                firstError = firstError ?? error
            }

            let localURL = localFileURL(for: item)
            modelContext.delete(item)

            if let localURL {
                do {
                    try services.downloadClient.deleteLocalDownload(fileURL: localURL)
                } catch {
                    firstError = firstError ?? error
                }
            }
        }
        do {
            try modelContext.save()
        } catch {
            firstError = firstError ?? error
        }
        if let firstError {
            alertMessage = .error(firstError.localizedDescription)
        }
    }

    private var downloadGroupNames: [String] {
        var names = Set(downloadGroups.map { normalizedDownloadGroupName($0.name) })
        names.formUnion(queue.map { normalizedDownloadGroupName($0.downloadGroupName) })
        names.insert(defaultDownloadGroupName)
        return names.sorted { lhs, rhs in
            if lhs == defaultDownloadGroupName { return true }
            if rhs == defaultDownloadGroupName { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private func createDownloadGroup(named rawName: String) {
        let name = normalizedDownloadGroupName(rawName)
        guard name != defaultDownloadGroupName else {
            alertMessage = .error("Default group exists")
            return
        }
        guard !downloadGroupNames.contains(name) else {
            alertMessage = .error("\(name) already exists")
            return
        }
        modelContext.insert(DownloadGroupRecord(name: name))
        try? modelContext.save()
        toastMessage = .success("Created group: \(name)")
    }

    private func moveDownloadItem(_ item: DownloadQueueRecord, to groupName: String) {
        item.downloadGroupName = normalizedDownloadGroupName(groupName)
        try? modelContext.save()
        toastMessage = .success("Moved to \(item.downloadGroupName)")
    }

    private func renameDownloadGroup(from oldName: String, to newName: String) {
        let oldName = normalizedDownloadGroupName(oldName)
        let newName = normalizedDownloadGroupName(newName)
        guard oldName != newName else { return }
        for item in queue where normalizedDownloadGroupName(item.downloadGroupName) == oldName {
            item.downloadGroupName = newName
        }
        if let oldRecord = downloadGroups.first(where: { normalizedDownloadGroupName($0.name) == oldName }) {
            modelContext.delete(oldRecord)
        }
        if newName != defaultDownloadGroupName,
           !downloadGroups.contains(where: { normalizedDownloadGroupName($0.name) == newName }) {
            modelContext.insert(DownloadGroupRecord(name: newName))
        }
        try? modelContext.save()
        toastMessage = .success("Renamed to \(newName)")
    }

    private func deleteDownloadGroup(_ name: String) {
        let name = normalizedDownloadGroupName(name)
        for item in queue where normalizedDownloadGroupName(item.downloadGroupName) == name {
            item.downloadGroupName = defaultDownloadGroupName
        }
        if let record = downloadGroups.first(where: { normalizedDownloadGroupName($0.name) == name }) {
            modelContext.delete(record)
        }
        try? modelContext.save()
        toastMessage = .success("Moved videos from \(name) to Default Group")
    }

    private func localFileURL(for item: DownloadQueueRecord) -> URL? {
        guard let localFileURLString = item.localFileURLString,
              let url = URL(string: localFileURLString) else {
            return nil
        }
        return url
    }

    private var shouldConfirmMobileDataDownload: Bool {
        warnBeforeMobileDataDownload && services.networkMonitor.shouldTreatAsMetered
    }

    private var mobileDataAlertBinding: Binding<Bool> {
        Binding {
            mobileDataDownloadID != nil
        } set: { isPresented in
            if !isPresented {
                mobileDataDownloadID = nil
            }
        }
    }

    private func continueAfterMobileDataWarning() {
        guard let id = mobileDataDownloadID else { return }
        mobileDataDownloadID = nil
        guard let item = queue.first(where: { $0.id == id }) else { return }
        Task { await startDownload(item) }
    }

    private func scanLocalDownloads() {
        Task {
            await synchronizeDownloadRecords(showStatus: true)
        }
    }

    private func synchronizeDownloadRecords(showStatus: Bool) async {
        let localFileResult = Result { try services.downloadClient.localDownloads() }
        await HanaDownloadRecordSynchronizer.synchronize(
            downloadClient: services.downloadClient,
            modelContext: modelContext,
            records: queue
        )

        guard showStatus else { return }
        switch localFileResult {
        case .success(let files) where files.isEmpty:
            toastMessage = .info("No local download files found.")
        case .success(let files):
            toastMessage = .success("Synced \(files.count) local files.")
        case .failure(let error):
            alertMessage = .error(error.localizedDescription)
        }
    }

}

private struct DownloadQueueList: View {
    let items: [DownloadQueueRecord]
    let groupNames: [String]
    let progressProvider: (String) -> Double?
    let isDownloadingProvider: (String) -> Bool
    let onStart: (DownloadQueueRecord) -> Void
    let onPause: (DownloadQueueRecord) -> Void
    let onResume: (DownloadQueueRecord) -> Void
    let onCancel: (DownloadQueueRecord) -> Void
    let onPlay: (DownloadQueueRecord, URL) -> Void
    let onDelete: (IndexSet) -> Void
    let onMoveGroup: (DownloadQueueRecord) -> Void
    var isEditing = false
    var selectedDownloadIDs = Set<String>()
    var onToggleSelection: (String) -> Void = { _ in }
    @AppStorage(HanaSettingsKey.collapsedDownloadGroupIDs) private var collapsedGroupIDsRawValue = "[]"

    var body: some View {
        Group {
            if groups.isEmpty {
                Section {
                    ContentUnavailableView("No downloaded videos", systemImage: "arrow.down.circle")
                }
            } else {
                Section {
                    ForEach(groups) { group in
                        DisclosureGroup(isExpanded: groupExpansionBinding(group.id)) {
                            if isEditing {
                                ForEach(group.items) { item in
                                    HanaSelectableRow(
                                        isSelected: selectedDownloadIDs.contains(item.id),
                                        accessibilityLabel: item.title
                                    ) {
                                        onToggleSelection(item.id)
                                    } content: {
                                        DownloadQueueSelectionRow(
                                            item: item,
                                            progress: progressProvider(item.id),
                                            isDownloading: isDownloadingProvider(item.id)
                                        )
                                    }
                                }
                            } else {
                                ForEach(group.items) { item in
                                    DownloadQueueRow(
                                        item: item,
                                        progress: progressProvider(item.id),
                                        isDownloading: isDownloadingProvider(item.id),
                                        onStart: {
                                            onStart(item)
                                        },
                                        onPause: {
                                            onPause(item)
                                        },
                                        onResume: {
                                            onResume(item)
                                        },
                                        onCancel: {
                                            onCancel(item)
                                        },
                                        onPlay: { url in
                                            onPlay(item, url)
                                        },
                                        onMoveGroup: {
                                            onMoveGroup(item)
                                        }
                                    )
                                }
                                .onDelete { offsets in
                                    onDelete(globalOffsets(for: group, offsets: offsets))
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title)
                                    .lineLimit(1)
                                Text("\(group.items.count) files")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: validGroupIDs, initial: true) { _, validGroupIDs in
            let prunedRawValue = DownloadGroupExpansionState.pruning(
                collapsedGroupIDsRawValue,
                validGroupIDs: validGroupIDs
            )
            if prunedRawValue != collapsedGroupIDsRawValue {
                collapsedGroupIDsRawValue = prunedRawValue
            }
        }
    }

    private var displayItems: [DownloadQueueRecord] {
        items.filter(\.shouldAppearInDownloads)
    }

    private var groups: [DownloadQueueGroup] {
        let recordsByGroup = Dictionary(grouping: displayItems) { item in
            normalizedDownloadGroupName(item.downloadGroupName)
        }
        let names = Set(groupNames).union(recordsByGroup.keys)
        return names.compactMap { groupName in
            let records = recordsByGroup[groupName, default: []]
            guard !records.isEmpty || groupName != defaultDownloadGroupName else {
                return nil
            }
            let sortedRecords = records.sorted { $0.createdAt > $1.createdAt }
            return DownloadQueueGroup(
                id: groupName,
                title: groupName,
                items: sortedRecords
            )
        }
        .sorted { lhs, rhs in
                if lhs.items.isEmpty != rhs.items.isEmpty {
                    return !lhs.items.isEmpty
                }
                let leftDate = lhs.items.map(\.createdAt).max() ?? .distantPast
                let rightDate = rhs.items.map(\.createdAt).max() ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                if lhs.title == defaultDownloadGroupName { return true }
                if rhs.title == defaultDownloadGroupName { return false }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    private var validGroupIDs: Set<String> {
        Set(groups.map(\.id))
    }

    private func groupExpansionBinding(_ id: String) -> Binding<Bool> {
        Binding {
            !DownloadGroupExpansionState.collapsedGroupIDs(from: collapsedGroupIDsRawValue).contains(id)
        } set: { isExpanded in
            var collapsedGroupIDs = DownloadGroupExpansionState.collapsedGroupIDs(
                from: collapsedGroupIDsRawValue
            )
            if isExpanded {
                collapsedGroupIDs.remove(id)
            } else {
                collapsedGroupIDs.insert(id)
            }
            collapsedGroupIDsRawValue = DownloadGroupExpansionState.rawValue(for: collapsedGroupIDs)
        }
    }

    private func globalOffsets(for group: DownloadQueueGroup, offsets: IndexSet) -> IndexSet {
        IndexSet(offsets.compactMap { groupIndex in
            let item = group.items[groupIndex]
            return items.firstIndex { $0.id == item.id }
        })
    }
}

private struct DownloadQueueGroup: Identifiable {
    let id: String
    let title: String
    let items: [DownloadQueueRecord]
}

private struct DownloadQueueSelectionRow: View {
    let item: DownloadQueueRecord
    let progress: Double?
    let isDownloading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label(item.quality, systemImage: "slider.horizontal.3")
                Label(item.status, systemImage: statusIcon)
                if let fileSizeText {
                    Text(fileSizeText)
                }
            }
            .labelStyle(DownloadInfoLabelStyle())
            .font(.caption)
            .foregroundStyle(.secondary)

            if shouldShowProgress {
                ProgressView(value: progress ?? item.progress)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch item.status {
        case "Completed":
            "checkmark.circle"
        case "Downloading":
            "arrow.down.circle"
        case "Paused":
            "pause.circle"
        case "Temporarily Failed":
            "wifi.exclamationmark"
        case "Download Failed":
            "exclamationmark.triangle"
        case "Cancelled":
            "xmark.circle"
        default:
            "clock"
        }
    }

    private var shouldShowProgress: Bool {
        item.status == "Downloading" || (item.progress > 0 && item.status != "Completed" && item.status != "Cancelled")
    }

    private var fileSizeText: String? {
        guard item.status == "Completed" else { return nil }
        return item.errorMessage
    }
}

private struct DownloadQueueRow: View {
    let item: DownloadQueueRecord
    let progress: Double?
    let isDownloading: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onPlay: (URL) -> Void
    let onMoveGroup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label(item.quality, systemImage: "slider.horizontal.3")
                Label(item.status, systemImage: statusIcon)
                if let fileSizeText {
                    Text(fileSizeText)
                }
            }
            .labelStyle(DownloadInfoLabelStyle())
            .font(.caption)
            .foregroundStyle(.secondary)

            if shouldShowProgress {
                if let progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView(value: item.progress)
                }
            }

            if let message = statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if item.retryCount > 0 {
                    Text("Attempt \(item.retryCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if shouldShowStartButton {
                    Button(action: onStart) {
                        Label(startTitle, systemImage: startIcon)
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(startTitle)
                    .disabled(isDownloading || !canStart)
                }

                if let localURL = item.existingLocalFileURL {
                    Button {
                        onPlay(localURL)
                    } label: {
                        Label("Play", systemImage: "play.circle")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Play")
                }

                Menu {
                    Button(action: onMoveGroup) {
                        Label("Move to Group", systemImage: "folder")
                    }

                    if let localURL = item.existingLocalFileURL {
                        ShareLink(item: localURL) {
                            Label("Share File", systemImage: "square.and.arrow.up")
                        }
                    }

                    if item.status == "Paused" {
                        Button(action: onResume) {
                            Label("Resume Download", systemImage: "play.circle")
                        }
                    }
                    if isDownloading {
                        Button(action: onPause) {
                            Label("Pause Download", systemImage: "pause.circle")
                        }

                        Button(role: .cancel, action: onCancel) {
                            Label("Cancel Download", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch item.status {
        case "Completed":
            "checkmark.circle"
        case "Downloading":
            "arrow.down.circle"
        case "Paused":
            "pause.circle"
        case "Temporarily Failed":
            "wifi.exclamationmark"
        case "Download Failed":
            "exclamationmark.triangle"
        case "Cancelled":
            "xmark.circle"
        default:
            "clock"
        }
    }

    private var statusMessage: String? {
        guard item.status != "Completed" else { return nil }
        return item.errorMessage
    }

    private var fileSizeText: String? {
        guard item.status == "Completed" else { return nil }
        return item.errorMessage
    }

    private var shouldShowStartButton: Bool {
        canStart && !isDownloading && item.status != "Completed"
    }

    private var startTitle: String {
        switch item.status {
        case "Paused", "Temporarily Failed":
            "Resume Download"
        case "Download Failed", "Cancelled":
            "Redownload"
        default:
            "Start Download"
        }
    }

    private var startIcon: String {
        switch item.status {
        case "Paused", "Temporarily Failed":
            "play"
        case "Download Failed", "Cancelled":
            "arrow.clockwise"
        default:
            "arrow.down"
        }
    }

    private var shouldShowProgress: Bool {
        item.status == "Downloading" || (item.progress > 0 && item.status != "Completed" && item.status != "Cancelled")
    }

    private var canStart: Bool {
        !item.mediaURLString.hasPrefix("file://")
    }
}

private struct DownloadInfoLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}

private extension DownloadQueueRecord {
    var existingLocalFileURL: URL? {
        guard let localFileURLString,
              let url = URL(string: localFileURLString),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    var shouldAppearInDownloads: Bool {
        status == "Completed" ? existingLocalFileURL != nil : true
    }
}

private struct DownloadMoveGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: DownloadQueueRecord
    let groupNames: [String]
    let onMove: (DownloadQueueRecord, String) -> Void
    @State private var selectedGroupName: String

    init(
        item: DownloadQueueRecord,
        groupNames: [String],
        onMove: @escaping (DownloadQueueRecord, String) -> Void
    ) {
        self.item = item
        self.groupNames = groupNames
        self.onMove = onMove
        _selectedGroupName = State(initialValue: normalizedDownloadGroupName(item.downloadGroupName))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Video") {
                    Text(item.title)
                    LabeledContent("Current Group", value: normalizedDownloadGroupName(item.downloadGroupName))
                }

                Section("Existing Groups") {
                    Picker("Move to", selection: $selectedGroupName) {
                        ForEach(groupNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
            }
            .navigationTitle("Move to Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HanaToolbarIconButton(title: "Save", systemImage: "checkmark") {
                        onMove(item, selectedGroupName)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DownloadGroupManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    let groupNames: [String]
    let onRename: (String, String) -> Void
    let onDelete: (String) -> Void
    @State private var renamingGroupName: String?
    @State private var renameText = ""
    @State private var deletingGroupName: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Group") {
                    ForEach(groupNames, id: \.self) { name in
                        HStack {
                            Label(name, systemImage: "folder")
                            Spacer()
                            Menu {
                                Button {
                                    renamingGroupName = name
                                    renameText = name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    deletingGroupName = name
                                } label: {
                                    Label("Move to Default Group", systemImage: "arrow.uturn.backward")
                                }
                                .disabled(name == defaultDownloadGroupName)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Group Management")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    HanaToolbarIconButton(title: "Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .alert("Rename Group", isPresented: renameAlertBinding) {
                TextField("Group Name", text: $renameText)
                Button("Save") {
                    guard let renamingGroupName else { return }
                    onRename(renamingGroupName, renameText)
                    self.renamingGroupName = nil
                }
                Button("Cancel", role: .cancel) {
                    renamingGroupName = nil
                }
            }
            .confirmationDialog("Move videos in this group back to Default?", isPresented: deleteConfirmationBinding, titleVisibility: .visible) {
                Button("Move to Default Group", role: .destructive) {
                    guard let deletingGroupName else { return }
                    onDelete(deletingGroupName)
                    self.deletingGroupName = nil
                }
                Button("Cancel", role: .cancel) {
                    deletingGroupName = nil
                }
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding {
            renamingGroupName != nil
        } set: { isPresented in
            if !isPresented {
                renamingGroupName = nil
            }
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding {
            deletingGroupName != nil
        } set: { isPresented in
            if !isPresented {
                deletingGroupName = nil
            }
        }
    }
}

private func normalizedDownloadGroupName(_ value: String?) -> String {
    value?.nilIfEmpty ?? defaultDownloadGroupName
}

private struct LocalVideoPlayback: Identifiable {
    let id = UUID()
    let fileURL: URL
    let title: String
}

private struct LocalVideoPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HanaSettingsKey.loopPlaybackEnabled) private var loopPlaybackEnabled = false
    let playback: LocalVideoPlayback
    @State private var player: AVPlayer?
    @State private var playbackLoopController = HanaPlaybackLoopController()

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .background(.black)
                .ignoresSafeArea(edges: .bottom)
            .navigationTitle(playback.title)
#if os(iOS) || os(visionOS)
            .hanaInlineNavigationTitleDisplayMode()
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    HanaToolbarIconButton(title: "Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                HanaPlaybackAudioSession.activateForVideoPlayback()
                let nextPlayer = AVPlayer(url: playback.fileURL)
                nextPlayer.isMuted = false
                nextPlayer.volume = 1.0
                player = nextPlayer
                configurePlaybackLoop(player: nextPlayer)
                nextPlayer.play()
            }
            .onChange(of: loopPlaybackEnabled) {
                configurePlaybackLoop(player: player)
            }
            .onDisappear {
                playbackLoopController.invalidate()
                player?.pause()
                HanaPlaybackAudioSession.deactivateAfterPlayback()
            }
        }
    }

    private func configurePlaybackLoop(player: AVPlayer?) {
        playbackLoopController.configure(
            player: player,
            item: player?.currentItem,
            isLoopingEnabled: loopPlaybackEnabled
        )
    }
}
