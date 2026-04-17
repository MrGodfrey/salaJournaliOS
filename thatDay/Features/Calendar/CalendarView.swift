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
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 7)
    private let calendar = AppLanguage.calendar

    private var displayedYear: Int {
        calendar.component(.year, from: store.displayedMonth)
    }

    private var displayedMonthValue: Int {
        calendar.component(.month, from: store.displayedMonth)
    }

    private var displayedMonthTitle: String {
        AppLanguage.monthTitle(for: store.displayedMonth)
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
                    HStack(spacing: 12) {
                        Button {
                            store.previousMonth()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button {
                                presentMonthPicker()
                            } label: {
                                HStack(spacing: 4) {
                                    Text(String(displayedYear))
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(displayedYear))
                            .accessibilityIdentifier("calendarYearPickerButton")

                            Button {
                                presentMonthPicker()
                            } label: {
                                HStack(spacing: 4) {
                                    Text(displayedMonthTitle)
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(displayedMonthTitle)
                            .accessibilityIdentifier("calendarMonthPickerButton")
                        }

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button("NOW") {
                        store.returnToToday()
                    }
                    .font(.footnote.bold())
                    .accessibilityIdentifier("calendarNowButton")
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

    private func presentMonthPicker() {
        pickerSelection = CalendarPickerSelection(
            year: displayedYear,
            month: displayedMonthValue
        )
        isShowingMonthPicker = true
    }
}
