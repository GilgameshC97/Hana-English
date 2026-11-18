import SwiftData
import SwiftUI

struct HKeyframeManagementScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HKeyframeRecord.updatedAt, order: .reverse) private var records: [HKeyframeRecord]
    @State private var query = ""
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?

    private var visibleRecords: [HKeyframeRecord] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return records }
        return records.filter {
            $0.title.localizedStandardContains(text)
                || $0.videoCode.localizedStandardContains(text)
                || ($0.groupTitle?.localizedStandardContains(text) ?? false)
        }
    }

    var body: some View {
        content
            .navigationTitle("HKeyframes")
            .searchable(text: $query, prompt: "Title or Code")
            .hanaToast($toastMessage)
            .hanaFeedbackAlert($alertMessage)
    }

    @ViewBuilder
    private var content: some View {
        if records.isEmpty {
            ContentUnavailableView {
                Label("No local HKeyframes", systemImage: "bookmark")
            } description: {
                Text("Imported keyframes will appear here.")
            } actions: {
                importButton
                    .buttonStyle(.borderedProminent)
            }
        } else if visibleRecords.isEmpty {
            ContentUnavailableView("No matching HKeyframes", systemImage: "line.3.horizontal.decrease.circle")
        } else {
            hKeyframeList
        }
    }

    private var hKeyframeList: some View {
        List {
            Section {
                importButton
            }

            Section("Local HKeyframes") {
                recordRows
            }
        }
    }

    private var importButton: some View {
        Button {
            importFromPasteboard()
        } label: {
            Label("Import from Clipboard", systemImage: "doc.on.clipboard")
        }
    }

    private var recordRows: some View {
        ForEach(visibleRecords) { record in
            NavigationLink {
                HKeyframeRecordDetailScreen(record: record)
            } label: {
                HKeyframeRecordRow(record: record)
            }
        }
        .onDelete(perform: delete)
    }

    private func importFromPasteboard() {
        do {
            guard let text = HanaPasteboard.string else {
                throw HanaHKeyframeImportError.invalidShareText
            }
            let record = try HanaHKeyframeLibrary.decodeShareText(text)
            let videoCode = record.videoCode
            try? modelContext.delete(
                model: HKeyframeRecord.self,
                where: #Predicate<HKeyframeRecord> { item in
                    item.videoCode == videoCode
                }
            )
            modelContext.insert(record)
            try modelContext.save()
            toastMessage = .success("Imported \(record.title)")
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for offset in offsets {
            modelContext.delete(visibleRecords[offset])
        }
        try? modelContext.save()
    }
}

private struct HKeyframeRecordRow: View {
    let record: HKeyframeRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(record.keyframes.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Label(record.videoCode, systemImage: "number")
                if let groupTitle = record.groupTitle {
                    Text(groupTitle)
                }
                if let author = record.author {
                    Text(author)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

struct HKeyframeRecordDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var record: HKeyframeRecord
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?
    @State private var editingKeyframe: HKeyframeEntry?
    @State private var isManualAddPresented = false

    var body: some View {
        detailContent
            .navigationTitle("HKeyframes")
            .hanaToast($toastMessage)
            .hanaFeedbackAlert($alertMessage)
            .onDisappear {
                try? modelContext.save()
            }
            .sheet(item: $editingKeyframe) { keyframe in
                HKeyframeEditSheet(
                    title: "Edit Keyframe",
                    initialPositionMilliseconds: keyframe.positionMilliseconds,
                    initialPrompt: keyframe.prompt ?? ""
                ) { updated in
                    record.replace(keyframe, with: updated)
                    try? modelContext.save()
                }
            }
            .sheet(isPresented: $isManualAddPresented) {
                HKeyframeEditSheet(
                    title: "Add Keyframe",
                    initialPositionMilliseconds: 0,
                    initialPrompt: ""
                ) { keyframe in
                    record.append(keyframe)
                    try? modelContext.save()
                }
            }
    }

    @ViewBuilder
    private var detailContent: some View {
#if os(macOS)
        macOSDetailContent
#else
        detailForm
#endif
    }

    private var detailForm: some View {
        Form {
            Section("Info") {
                TextField("Title", text: $record.title)
                TextField("Series", text: Binding(
                    get: { record.groupTitle ?? "" },
                    set: { record.groupTitle = $0.nilIfEmpty }
                ))
                TextField("Episode", value: $record.episode, format: .number)
                LabeledContent("Code", value: record.videoCode)
            }

            Section("Keyframes") {
                if record.keyframes.isEmpty {
                    ContentUnavailableView("No Keyframes", systemImage: "bookmark.slash")
                } else {
                    ForEach(record.keyframes) { keyframe in
                        HStack {
                            Button {
                                editingKeyframe = keyframe
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formatTime(keyframe.seconds))
                                        .font(.headline)
                                    if let prompt = keyframe.prompt {
                                        Text(prompt)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                editingKeyframe = keyframe
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)

                            Button(role: .destructive) {
                                record.remove(keyframe)
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Button {
                    isManualAddPresented = true
                } label: {
                    Label("Add Keyframe Manually", systemImage: "plus.circle")
                }
            }

            Section {
                Button {
                    copyShareText()
                } label: {
                    Label("Copy Share Text", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    deleteRecord()
                } label: {
                    Label("Delete Group", systemImage: "trash")
                }
            }
        }
    }

#if os(macOS)
    private var macOSDetailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                macOSInfoSection

                Divider()

                macOSKeyframeSection

                Divider()

                macOSActionRow
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var macOSInfoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Info")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    macOSFieldLabel("Title:")
                    TextField("Title", text: $record.title)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                }

                GridRow {
                    macOSFieldLabel("Series:")
                    TextField("Series", text: Binding(
                        get: { record.groupTitle ?? "" },
                        set: { record.groupTitle = $0.nilIfEmpty }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                }

                GridRow {
                    macOSFieldLabel("Episode:")
                    TextField("Episode", value: $record.episode, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }

                GridRow {
                    macOSFieldLabel("Code:")
                    Text(record.videoCode)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var macOSKeyframeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Keyframes")
                    .font(.headline)
                Spacer()
                Button {
                    isManualAddPresented = true
                } label: {
                    Label("Add Keyframe", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if record.keyframes.isEmpty {
                ContentUnavailableView("No Keyframes", systemImage: "bookmark.slash")
                    .frame(height: 140)
            } else {
                macOSKeyframeRows
            }
        }
    }

    private var macOSKeyframeRows: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Time")
                    .frame(width: 120, alignment: .leading)
                Text("Tip")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Actions")
                    .frame(width: 96, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ForEach(record.keyframes) { keyframe in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(formatTime(keyframe.seconds))
                        .font(.body.monospacedDigit())
                        .frame(width: 120, alignment: .leading)

                    Text(keyframe.prompt ?? "None")
                        .foregroundStyle(keyframe.prompt == nil ? .secondary : .primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        Button {
                            editingKeyframe = keyframe
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit")

                        Button(role: .destructive) {
                            delete(keyframe)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete")
                    }
                    .frame(width: 96, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                if keyframe.id != record.keyframes.last?.id {
                    Divider()
                }
            }
        }
        .overlay(alignment: .top) {
            Divider()
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var macOSActionRow: some View {
        HStack {
            Button {
                copyShareText()
            } label: {
                Label("Copy Share Text", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(role: .destructive) {
                deleteRecord()
            } label: {
                Label("Delete Group", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    private func macOSFieldLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 64, alignment: .trailing)
    }
#endif

    private func copyShareText() {
        do {
            HanaPasteboard.string = try HanaHKeyframeLibrary.shareText(for: record)
            toastMessage = .success("Copied to Clipboard")
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }

    private func delete(_ keyframe: HKeyframeEntry) {
        record.remove(keyframe)
        try? modelContext.save()
    }

    private func deleteRecord() {
        modelContext.delete(record)
        try? modelContext.save()
        dismiss()
    }
}
