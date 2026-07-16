import Foundation

enum AppLanguage {
    static var locale: Locale {
        L10n.locale
    }

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

    static func monthDayTitle(for date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        format(date, template: "MMMMd", timeZone: timeZone)
    }

    static func monthTitle(for date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        format(date, template: "MMMM", timeZone: timeZone)
    }

    static func monthYearTitle(for date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        format(date, template: "yMMMM", timeZone: timeZone)
    }

    static func weekdayTitle(for date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        format(date, template: "EEEE", timeZone: timeZone)
    }

    static func timelineTitle(for date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        format(date, template: "yMMMMd", timeZone: timeZone)
    }

    static func cardDateTitle(for date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        if prefersChineseDateFormats {
            return format(date, pattern: "yyyy年M月d日 EEEE", timeZone: timeZone)
        }

        return format(date, pattern: "EEEE, M/d/yyyy", timeZone: timeZone)
    }

    static func journalCardDateTitle(for date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        if prefersChineseDateFormats {
            return format(date, pattern: "yyyy年 EEEE", timeZone: timeZone)
        }

        return format(date, pattern: "EEEE, yyyy", timeZone: timeZone)
    }

    static func yearTitle(for date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        format(date, template: "y", timeZone: timeZone)
    }

    private static func format(_ date: Date, template: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar(in: timeZone)
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static func format(_ date: Date, pattern: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar(in: timeZone)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        return configuredCalendar
    }

    private static var prefersChineseDateFormats: Bool {
        locale.identifier.hasPrefix("zh")
    }
}
