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

    static func monthDayTitle(for date: Date) -> String {
        format(date, template: "MMMMd")
    }

    static func monthTitle(for date: Date) -> String {
        format(date, template: "MMMM")
    }

    static func monthYearTitle(for date: Date) -> String {
        format(date, template: "yMMMM")
    }

    static func weekdayTitle(for date: Date) -> String {
        format(date, template: "EEEE")
    }

    static func timelineTitle(for date: Date) -> String {
        format(date, template: "yMMMMd")
    }

    static func cardDateTitle(for date: Date) -> String {
        if prefersChineseDateFormats {
            return format(date, pattern: "yyyy年M月d日 EEEE")
        }

        return format(date, pattern: "EEEE, M/d/yyyy")
    }

    static func journalCardDateTitle(for date: Date) -> String {
        if prefersChineseDateFormats {
            return format(date, pattern: "yyyy年 EEEE")
        }

        return format(date, pattern: "EEEE, yyyy")
    }

    static func yearTitle(for date: Date) -> String {
        format(date, template: "y")
    }

    private static func format(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static var prefersChineseDateFormats: Bool {
        locale.identifier.hasPrefix("zh")
    }
}
