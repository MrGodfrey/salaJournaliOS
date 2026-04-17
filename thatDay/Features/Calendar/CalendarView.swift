import Observation
import SwiftUI

private struct CalendarPickerSelection {
    var year: Int
    var month: Int
}

struct CalendarView: View {
    @Bindable var store: AppStore

    @State private var isShowingMonthPicker = false
    @State private var pickerSelection = CalendarPickerSelection(year: 2026, month: 4)

    private let weekdaySymbols = AppLanguage.shortStandaloneWeekdaySymbols
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let statisticsColumns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
    private let calendar = AppLanguage.calendar

    private var displayedYear: Int {
        calendar.component(.year, from: store.displayedMonth)
    }

    private var displayedMonthValue: Int {
        calendar.component(.month, from: store.displayedMonth)
    }

    private var displayedMonthTitle: String {
        AppLanguage.monthYearTitle(for: store.displayedMonth)
    }

    private var yearRange: [Int] {
        Array(1900...2100)
    }

    var body: some View {
        let days = CalendarGridBuilder.makeMonthGrid(
            displayedMonth: store.displayedMonth,
            selectedDate: store.selectedDate,
            journalDates: store.journalDates
        )

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    calendarPanel(days: days)

                    LazyVGrid(columns: statisticsColumns, spacing: 16) {
                        StatisticCard(
                            title: "JOURNALED",
                            value: String(store.journalEntryCount),
                            systemImage: "book.closed",
                            unit: "POSTS",
                            colors: [Color(red: 0.86, green: 0.32, blue: 0.39), Color(red: 0.61, green: 0.18, blue: 0.35)]
                        )

                        StatisticCard(
                            title: "BLOGS",
                            value: String(store.blogEntryCount),
                            systemImage: "calendar",
                            unit: "POSTS",
                            colors: [Color(red: 0.34, green: 0.35, blue: 0.86), Color(red: 0.20, green: 0.21, blue: 0.67)]
                        )

                        StatisticCard(
                            title: "WRITTEN",
                            value: store.formattedWrittenWordCount,
                            systemImage: "pencil.and.scribble",
                            unit: "WORDS",
                            colors: [Color(red: 0.88, green: 0.48, blue: 0.34), Color(red: 0.74, green: 0.34, blue: 0.21)]
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        store.returnToToday()
                    }
                    .accessibilityIdentifier("calendarTodayButton")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.presentSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("calendarOpenSettingsButton")
                }
            }
            .sheet(isPresented: $isShowingMonthPicker) {
                NavigationStack {
                    HStack(spacing: 0) {
                        Picker("Year", selection: $pickerSelection.year) {
                            ForEach(yearRange, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .pickerStyle(.wheel)
                        .accessibilityIdentifier("calendarYearWheel")

                        Picker("Month", selection: $pickerSelection.month) {
                            ForEach(1...12, id: \.self) { month in
                                Text(AppLanguage.monthSymbols[month - 1]).tag(month)
                            }
                        }
                        .pickerStyle(.wheel)
                        .accessibilityIdentifier("calendarMonthWheel")
                    }
                    .navigationTitle("Choose Month and Year")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                isShowingMonthPicker = false
                            }
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                store.setDisplayedMonth(
                                    year: pickerSelection.year,
                                    month: pickerSelection.month
                                )
                                isShowingMonthPicker = false
                            }
                            .accessibilityIdentifier("calendarPickerDoneButton")
                        }
                    }
                }
                .presentationDetents([.height(320)])
            }
        }
    }

    private func calendarPanel(days: [CalendarDay]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 16) {
                Button {
                    presentMonthPicker()
                } label: {
                    HStack(spacing: 8) {
                        Text(displayedMonthTitle)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.primary)

                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("calendarMonthPickerButton")

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        store.previousMonth()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.indigo)
                            .frame(width: 36, height: 36)
                            .background(Color.indigo.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("calendarPreviousMonthButton")

                    Button {
                        store.nextMonth()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.indigo)
                            .frame(width: 36, height: 36)
                            .background(Color.indigo.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("calendarNextMonthButton")
                }
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(days) { day in
                    Button {
                        store.goToJournal(for: day.date)
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(day.isSelected ? Color.indigo.opacity(0.18) : Color.clear)
                                    .frame(width: 34, height: 34)

                                Text("\(day.dayNumber)")
                                    .font(.body.weight(day.isSelected ? .bold : .medium))
                                    .foregroundStyle(day.isInDisplayedMonth ? Color.primary : Color.secondary.opacity(0.45))
                            }

                            Circle()
                                .fill(day.hasJournalEntries ? Color.indigo : Color.clear)
                                .frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("calendarDay-\(day.key)")
                }
            }
        }
        .padding(24)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
    }

    private func presentMonthPicker() {
        pickerSelection = CalendarPickerSelection(
            year: displayedYear,
            month: displayedMonthValue
        )
        isShowingMonthPicker = true
    }
}

private struct StatisticCard: View {
    let title: String
    let value: String
    let systemImage: String
    let unit: String
    let colors: [Color]

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white)

            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))

            Text(unit)
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.88))
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 172)
        .padding(.horizontal, 10)
        .background(
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: colors.last?.opacity(0.22) ?? .clear, radius: 16, y: 8)
    }
}
