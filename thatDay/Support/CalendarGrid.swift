import Foundation

struct CalendarDay: Identifiable, Equatable {
    var id: String { key }

    let date: Date
    let key: String
    let dayNumber: Int
    let isInDisplayedMonth: Bool
    let isSelected: Bool
    let hasJournalEntries: Bool
}

enum CalendarGridBuilder {
    static func makeMonthGrid(
        displayedMonth: Date,
        selectedDate: Date,
        journalDates: [Date],
        calendar: Calendar = .current
    ) -> [CalendarDay] {
        let monthStart = calendar.startOfMonth(for: displayedMonth)
        guard let monthRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }

        let displayedMonthValue = calendar.component(.month, from: monthStart)
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        let markerKeys = Set(journalDates.map { calendar.dayIdentifier(for: $0) })

        var days: [CalendarDay] = []

        for offset in (-leadingDays)..<monthRange.count {
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else {
                continue
            }

            days.append(
                CalendarDay(
                    date: date,
                    key: calendar.dayIdentifier(for: date),
                    dayNumber: calendar.component(.day, from: date),
                    isInDisplayedMonth: calendar.component(.month, from: date) == displayedMonthValue,
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    hasJournalEntries: markerKeys.contains(calendar.dayIdentifier(for: date))
                )
            )
        }

        while days.count % 7 != 0 {
            guard let date = calendar.date(byAdding: .day, value: days.count - leadingDays, to: monthStart) else {
                break
            }

            days.append(
                CalendarDay(
                    date: date,
                    key: calendar.dayIdentifier(for: date),
                    dayNumber: calendar.component(.day, from: date),
                    isInDisplayedMonth: false,
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    hasJournalEntries: markerKeys.contains(calendar.dayIdentifier(for: date))
                )
            )
        }

        return days
    }
}
