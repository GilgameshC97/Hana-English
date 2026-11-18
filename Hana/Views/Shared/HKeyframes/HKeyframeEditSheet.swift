import SwiftUI

struct HKeyframeEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (HKeyframeEntry) -> Void
    @State private var positionMilliseconds: Int64
    @State private var promptText: String

    init(
        title: String,
        initialPositionMilliseconds: Int64,
        initialPrompt: String = "",
        onSave: @escaping (HKeyframeEntry) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        _positionMilliseconds = State(initialValue: initialPositionMilliseconds)
        _promptText = State(initialValue: initialPrompt)
    }

    @ViewBuilder
    var body: some View {
#if os(macOS)
        macOSBody
#else
        mobileBody
#endif
    }

    private var mobileBody: some View {
        NavigationStack {
            Form {
                Section("Time") {
                    LabeledContent("Time", value: formatTime(TimeInterval(positionMilliseconds) / 1_000))
                    TextField("Position (ms)", value: $positionMilliseconds, format: .number)
                        .hanaNumberKeyboard()
                    HStack {
                        Button("-5s") { adjust(by: -5_000) }
                        Button("-1s") { adjust(by: -1_000) }
                        Button("+1s") { adjust(by: 1_000) }
                        Button("+5s") { adjust(by: 5_000) }
                    }
                    .buttonStyle(.bordered)
                }

                Section("Tip") {
                    TextField("Prompt (optional)", text: $promptText)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HanaToolbarIconButton(title: "Save", systemImage: "checkmark") {
                        save()
                    }
                    .disabled(positionMilliseconds < 0)
                }
            }
        }
    }

#if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    macOSFieldLabel("Preview:")
                    Text(formatTime(TimeInterval(positionMilliseconds) / 1_000))
                        .font(.body.monospacedDigit())
                }

                GridRow {
                    macOSFieldLabel("Position:")
                    TextField("Position (ms)", value: $positionMilliseconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }

                GridRow {
                    macOSFieldLabel("Adjust:")
                    HStack(spacing: 8) {
                        Button("-5s") { adjust(by: -5_000) }
                        Button("-1s") { adjust(by: -1_000) }
                        Button("+1s") { adjust(by: 1_000) }
                        Button("+5s") { adjust(by: 5_000) }
                    }
                    .buttonStyle(.bordered)
                }

                GridRow {
                    macOSFieldLabel("Prompt:")
                    TextField("Optional", text: $promptText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)

            Divider()

            HStack(spacing: 10) {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(positionMilliseconds < 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func macOSFieldLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 72, alignment: .trailing)
    }
#endif

    private func save() {
        onSave(HKeyframeEntry(
            positionMilliseconds: max(positionMilliseconds, 0),
            prompt: promptText
        ))
        dismiss()
    }

    private func adjust(by value: Int64) {
        positionMilliseconds = max(positionMilliseconds + value, 0)
    }
}
