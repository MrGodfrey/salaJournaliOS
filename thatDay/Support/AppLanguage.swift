import Foundation

enum AppLanguage {
    static let locale = Locale(identifier: "en_US")

    static var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = locale
        return calendar
    }

    static var shortStandaloneWeekdaySymbols: [String] {
        calendar.shortStandaloneWeekdaySymbols
    }

    static var monthSymbols: [String] {
        calendar.monthSymbols
    }

    static func monthDayTitle(for date: Date) -> String {
        monthDayFormatter.string(from: date)
    }

    static func monthTitle(for date: Date) -> String {
        monthFormatter.string(from: date)
    }

    static func weekdayTitle(for date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    static func timelineTitle(for date: Date) -> String {
        timelineFormatter.string(from: date)
    }

    static func cardDateTitle(for date: Date) -> String {
        cardDateFormatter.string(from: date)
    }

    private static let monthDayFormatter = makeFormatter(dateFormat: "MMMM d")
    private static let monthFormatter = makeFormatter(dateFormat: "MMMM")
    private static let weekdayFormatter = makeFormatter(dateFormat: "EEEE")
    private static let timelineFormatter = makeFormatter(dateFormat: "MMMM d, yyyy")
    private static let cardDateFormatter = makeFormatter(dateFormat: "EEEE, M/d/yyyy")

    private static func makeFormatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateFormat = dateFormat
        return formatter
    }
}
