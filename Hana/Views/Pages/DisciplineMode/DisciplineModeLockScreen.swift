import SwiftUI

struct DisciplineModeLockScreen: View {
    @Environment(DisciplineModeStore.self) private var disciplineModeStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let state = DisciplineModeEvaluator.evaluate(
                configuration: disciplineModeStore.configuration,
                now: context.date,
                calendar: .current
            )

            VStack(spacing: 18) {
                Image(systemName: "calendar.badge.lock")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.pink)

                VStack(spacing: 8) {
                    Text("Discipline Active")
                        .font(.title.bold())
                    Text(summaryText(for: state))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let remaining = state.remainingInterval {
                    Text(remainingText(remaining))
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }

                if let nextAvailableAt = state.nextAvailableAt {
                    Text("Available: \(DisciplineModeFormatting.chineseDateTimeText(for: nextAvailableAt))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        }
    }

    private func summaryText(for state: DisciplineModeState) -> String {
        if let currentCycleDay = state.currentCycleDay, let cycleLengthDays = state.cycleLengthDays {
            if state.scheduleKind == .weekly {
                let allowed = DisciplineModeFormatting.weekdayListText(for: state.allowedDayNumbers)
                let currentWeekday = DisciplineModeFormatting.weekdayText(for: currentCycleDay)
                return "Weekly cycle, today: \(currentWeekday). Allowed: \(allowed)."
            }
            let allowed = state.allowedDayNumbers.sorted().map { "Day \($0)" }.joined(separator: "、")
            return "\(cycleLengthDays)-day cycle, currently day \(currentCycleDay). Allowed: \(allowed)."
        }
        return "Access blocked until restriction ends."
    }

    private func remainingText(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
