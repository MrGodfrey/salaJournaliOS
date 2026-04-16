import Observation
import SwiftUI

struct CalendarView: View {
    @Bindable var store: AppStore

    private let weekdaySymbols = Calendar.current.shortStandaloneWeekdaySymbols
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 7)

    var body: some View {
        let days = CalendarGridBuilder.makeMonthGrid(
            displayedMonth: store.displayedMonth,
            selectedDate: store.selectedDate,
            journalDates: store.journalDates
        )

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button {
                            store.previousMonth()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                        }

                        Spacer()

                        Text(store.displayedMonth.formatted(.dateTime.year().month(.wide)))
                            .font(.title3.bold())

                        Spacer()

                        Button {
                            store.nextMonth()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.headline)
                        }
                    }
                    .padding(.horizontal, 4)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }

                        ForEach(days) { day in
                            Button {
                                store.goToJournal(for: day.date)
                            } label: {
                                VStack(spacing: 6) {
                                    Text("\(day.dayNumber)")
                                        .font(.body.weight(day.isSelected ? .bold : .regular))

                                    Circle()
                                        .fill(day.hasJournalEntries ? Color.indigo : Color.clear)
                                        .frame(width: 6, height: 6)
                                }
                                .foregroundStyle(day.isInDisplayedMonth ? Color.primary : Color.secondary.opacity(0.5))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .padding(.vertical, 6)
                                .background(day.isSelected ? Color.indigo.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("calendarDay-\(day.key)")
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Calendar")
        }
    }
}
