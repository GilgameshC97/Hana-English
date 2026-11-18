import Foundation

enum DisciplineModeFormatting {
    nonisolated static func chineseDateTimeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    nonisolated static func weekdayShortText(for weekdayNumber: Int) -> String {
        switch weekdayNumber {
        case 1:
            "Mon"
        case 2:
            "Tue"
        case 3:
            "Wed"
        case 4:
            "Thu"
        case 5:
            "Fri"
        case 6:
            "Sat"
        case 7:
            "Sun"
        default:
            "\(weekdayNumber)"
        }
    }

    nonisolated static func weekdayText(for weekdayNumber: Int) -> String {
        "\(weekdayShortText(for: weekdayNumber))"
    }

    nonisolated static func weekdayListText(for weekdayNumbers: Set<Int>) -> String {
        weekdayNumbers.sorted().map(weekdayText).joined(separator: "、")
    }
}
