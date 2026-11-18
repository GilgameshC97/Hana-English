import SwiftUI

struct DisciplineModeSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DisciplineModeStore.self) private var disciplineModeStore

    @State private var draftMode: DisciplineModeDraftMode = .weekly
    @State private var cycleLengthDays = 7
    @State private var weeklyAllowedWeekdayNumbers: Set<Int> = [1]
    @State private var recurringAllowedDayNumbers: Set<Int> = [1]
    @State private var singleDuration = DisciplineModeSingleDuration(days: 0, hours: 1, minutes: 0)
    @State private var showsConfirmation = false
    @State private var showsExitConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                introSection

                if canConfigure {
                    modeSection
                    configurationSection
                } else {
                    activeConfigurationSection
                }
            }
            .navigationTitle("Discipline Mode")
            .disciplineModeNavigationTitleStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "Disable", systemImage: "xmark") {
                        dismiss()
                    }
                }

                if canConfigure {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .destructive) {
                            showsConfirmation = true
                        } label: {
                            Label("Enable", systemImage: "lock")
                        }
                        .disabled(!canActivate)
                    }
                }
            }
            .alert("Cannot be undone once enabled", isPresented: $showsConfirmation) {
                Button("Enable Discipline Mode", role: .destructive) {
                    activate()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
            .alert("Exit Discipline Mode?", isPresented: $showsExitConfirmation) {
                Button("Exit Discipline Mode", role: .destructive) {
                    exitDisciplineMode()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Discipline Mode will be disabled until re-enabled.")
            }
        }
        .disciplineModeSheetPresentation()
        .onAppear {
            disciplineModeStore.refresh()
        }
    }

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "calendar.badge.lock")
                    .font(.headline)
                    .foregroundStyle(.pink)
                Text("Discipline starts now")
                    .font(.headline)
                Text("Discipline Mode restricts viewing during set periods to maintain focus. Once locked, it cannot be undone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var modeSection: some View {
        Section("Mode") {
            Picker("Mode", selection: $draftMode) {
                ForEach(DisciplineModeDraftMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var configurationSection: some View {
        switch draftMode {
        case .weekly:
            Section("Weekdays") {
                LabeledContent("Cycle Period", value: "7 Days")
                DisciplineModeAllowedDaysGrid(
                    cycleLengthDays: DisciplineModeWeeklyConfiguration.cycleLengthDays,
                    allowedDayNumbers: $weeklyAllowedWeekdayNumbers,
                    dayLabels: weekdayGridLabels,
                    accessibilityLabels: weekdayAccessibilityLabels
                )
                if !weeklyConfiguration.isValid {
                    Text("Select at least 1 day, but not the whole week.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        case .recurring:
            Section("Cycle") {
                Stepper(value: $cycleLengthDays, in: 2...30) {
                    LabeledContent("Cycle Period", value: "\(cycleLengthDays) Days")
                }
                DisciplineModeAllowedDaysGrid(
                    cycleLengthDays: cycleLengthDays,
                    allowedDayNumbers: $recurringAllowedDayNumbers
                )
                if !recurringConfiguration.isValid {
                    Text("Select at least 1 day, but not the entire cycle.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        case .single:
            Section("Duration") {
                DisciplineModeSingleDurationEditor(duration: $singleDuration)
                if !singleDuration.isValid {
                    Text("Duration must be greater than 0 minutes.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var activeConfigurationSection: some View {
        Section("Active Configuration") {
            Text(activeConfigurationText)
                .foregroundStyle(.secondary)
            if disciplineModeStore.state.allowsExit {
                Button(role: .destructive) {
                    showsExitConfirmation = true
                } label: {
                    Label("Exit Discipline Mode", systemImage: "lock.open")
                }
            } else {
                Text("Current configuration is active and cannot be modified.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var canConfigure: Bool {
        guard disciplineModeStore.configuration != nil else {
            return true
        }
        return disciplineModeStore.state.message != .active
    }

    private var weekdayGridLabels: [Int: String] {
        Dictionary(
            uniqueKeysWithValues: (1...DisciplineModeWeeklyConfiguration.cycleLengthDays).map { weekdayNumber in
                (weekdayNumber, DisciplineModeFormatting.weekdayShortText(for: weekdayNumber))
            }
        )
    }

    private var weekdayAccessibilityLabels: [Int: String] {
        Dictionary(
            uniqueKeysWithValues: (1...DisciplineModeWeeklyConfiguration.cycleLengthDays).map { weekdayNumber in
                (weekdayNumber, "\(DisciplineModeFormatting.weekdayShortText(for: weekdayNumber))")
            }
        )
    }

    private var recurringConfiguration: DisciplineModeRecurringConfiguration {
        DisciplineModeRecurringConfiguration(
            cycleLengthDays: cycleLengthDays,
            allowedDayNumbers: recurringAllowedDayNumbers
        )
    }

    private var weeklyConfiguration: DisciplineModeWeeklyConfiguration {
        DisciplineModeWeeklyConfiguration(
            allowedWeekdayNumbers: weeklyAllowedWeekdayNumbers
        )
    }

    private var canActivate: Bool {
        switch draftMode {
        case .weekly:
            weeklyConfiguration.isValid
        case .recurring:
            recurringConfiguration.isValid
        case .single:
            singleDuration.isValid
        }
    }

    private var summaryText: String {
        switch draftMode {
        case .weekly:
            let weekdays = DisciplineModeFormatting.weekdayListText(for: weeklyAllowedWeekdayNumbers)
            return "By Weekday
Allowed: \(weekdays).
Blocked on other days."
        case .recurring:
            let days = recurringAllowedDayNumbers.sorted().map { "Day \($0)" }.joined(separator: "、")
            return "\(cycleLengthDays)-day cycle
Allowed: \(days).
Blocked on other days."
        case .single:
            let until = Date.now.addingTimeInterval(singleDuration.totalSeconds)
            return "Locked until \(DisciplineModeFormatting.chineseDateTimeText(for: until))."
        }
    }

    private var confirmationMessage: String {
        summaryText
    }

    private var activeConfigurationText: String {
        guard let configuration = disciplineModeStore.configuration else {
            return "No active configuration."
        }

        switch configuration.mode {
        case .single(let until):
            return "Locked until \(DisciplineModeFormatting.chineseDateTimeText(for: until))."
        case .weekly(let weekly):
            let weekdays = DisciplineModeFormatting.weekdayListText(for: weekly.allowedWeekdayNumbers)
            return "Weekly; Allowed: \(weekdays)."
        case .recurring(let recurring):
            let days = recurring.allowedDayNumbers.sorted().map { "Day \($0)" }.joined(separator: "、")
            return "\(recurring.cycleLengthDays)-day cycle; Allowed: \(days)."
        }
    }

    private func activate() {
        let now = Date.now
        let mode: DisciplineModeMode

        switch draftMode {
        case .weekly:
            mode = .weekly(weeklyConfiguration)
        case .recurring:
            mode = .recurring(recurringConfiguration)
        case .single:
            mode = .single(until: now.addingTimeInterval(singleDuration.totalSeconds))
        }

        disciplineModeStore.activate(
            DisciplineModeConfiguration(createdAt: now, mode: mode)
        )
        dismiss()
    }

    private func exitDisciplineMode() {
        disciplineModeStore.clear()
        dismiss()
    }
}

private extension View {
    @ViewBuilder
    func disciplineModeSheetPresentation() -> some View {
#if os(macOS)
        self
#else
        presentationDetents([.medium, .large])
#endif
    }

    @ViewBuilder
    func disciplineModeNavigationTitleStyle() -> some View {
#if os(macOS)
        self
#else
        navigationBarTitleDisplayMode(.inline)
#endif
    }
}
