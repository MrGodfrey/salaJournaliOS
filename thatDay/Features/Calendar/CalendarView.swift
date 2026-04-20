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
    @State private var calendarGridWidth: CGFloat = 0
    @State private var firstWeekdayLabelWidth: CGFloat = 0

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

    private var monthTitleLeadingInset: CGFloat {
        guard calendarGridWidth > 0, firstWeekdayLabelWidth > 0 else {
            return 0
        }

        let columnWidth = calendarGridWidth / CGFloat(columns.count)
        return max((columnWidth - firstWeekdayLabelWidth) / 2, 0)
    }

    private var blogTagStatistics: [BlogTagStatisticItem] {
        Array(store.blogTags.enumerated()).map { index, tag in
            BlogTagStatisticItem(
                tag: tag,
                count: store.blogTagUsageCounts[tag, default: 0],
                style: BlogTagStatisticStyle.style(for: index)
            )
        }
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
                            unit: "POSTS",
                            colors: [Color(red: 0.86, green: 0.32, blue: 0.39), Color(red: 0.61, green: 0.18, blue: 0.35)]
                        )

                        StatisticCard(
                            title: "BLOGS",
                            value: String(store.blogEntryCount),
                            unit: "POSTS",
                            colors: [Color(red: 0.34, green: 0.35, blue: 0.86), Color(red: 0.20, green: 0.21, blue: 0.67)]
                        )

                        StatisticCard(
                            title: "WRITTEN",
                            value: store.formattedWrittenWordCount,
                            unit: "WORDS",
                            colors: [Color(red: 0.88, green: 0.48, blue: 0.34), Color(red: 0.74, green: 0.34, blue: 0.21)]
                        )
                    }

                    blogTagSection
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                Button {
                    presentMonthPicker()
                } label: {
                    HStack(spacing: 8) {
                        Text(displayedMonthTitle)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .allowsTightening(true)
                            .layoutPriority(1)

                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, monthTitleLeadingInset)
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

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol.uppercased())
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .background {
                            if index == 0 {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: CalendarWeekdayLabelWidthPreferenceKey.self,
                                        value: proxy.size.width
                                    )
                                }
                            }
                        }
                }

                ForEach(days) { day in
                    Button {
                        store.goToJournal(for: day.date)
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(day.isSelected ? Color.indigo.opacity(0.18) : Color.clear)
                                    .frame(width: 32, height: 32)

                                Text("\(day.dayNumber)")
                                    .font(.body.weight(day.isSelected ? .bold : .medium))
                                    .foregroundStyle(day.isInDisplayedMonth ? Color.primary : Color.secondary.opacity(0.45))
                            }

                            Circle()
                                .fill(day.hasJournalEntries ? Color.indigo : Color.clear)
                                .frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .padding(.vertical, 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("calendarDay-\(day.key)")
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CalendarGridWidthPreferenceKey.self,
                        value: proxy.size.width
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
        .onPreferenceChange(CalendarGridWidthPreferenceKey.self) { calendarGridWidth = $0 }
        .onPreferenceChange(CalendarWeekdayLabelWidthPreferenceKey.self) { firstWeekdayLabelWidth = $0 }
    }

    private var blogTagSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tags")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            TagStatisticFlowLayout(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(blogTagStatistics) { statistic in
                    Button {
                        store.openBlog(tag: statistic.tag)
                    } label: {
                        BlogTagStatisticButton(statistic: statistic)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("calendarBlogTagStat-\(statistic.accessibilityID)")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
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
    let unit: String
    let colors: [Color]

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.34)
                .allowsTightening(true)
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(unit)
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 112)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
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

private struct BlogTagStatisticButton: View {
    let statistic: BlogTagStatisticItem

    var body: some View {
        HStack(spacing: 12) {
            Text(statistic.tag)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Rectangle()
                .fill(statistic.style.foreground.opacity(0.18))
                .frame(width: 1, height: 22)

            Text(String(statistic.count))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(statistic.style.foreground)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(statistic.style.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(statistic.style.stroke, lineWidth: 1)
        )
        .shadow(color: statistic.style.shadow, radius: 12, y: 6)
    }
}

private struct TagStatisticFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat = 12, verticalSpacing: CGFloat = 12) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let rows = makeRows(maxWidth: maxWidth, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { partialResult, row in
            partialResult + row.height
        } + (rows.isEmpty ? 0 : CGFloat(rows.count - 1) * verticalSpacing)

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = makeRows(maxWidth: bounds.width, subviews: subviews)
        var currentY = bounds.minY

        for row in rows {
            var currentX = bounds.minX

            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: currentX, y: currentY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                currentX += item.size.width + horizontalSpacing
            }

            currentY += row.height + verticalSpacing
        }
    }

    private func makeRows(maxWidth: CGFloat, subviews: Subviews) -> [FlowRow] {
        guard !subviews.isEmpty else {
            return []
        }

        let availableWidth = max(maxWidth, 0)
        var rows: [FlowRow] = []
        var currentRow = FlowRow()

        for index in subviews.indices {
            let idealSize = subviews[index].sizeThatFits(.unspecified)
            let fittedWidth = availableWidth.isFinite ? min(idealSize.width, availableWidth) : idealSize.width
            let fittedSize = subviews[index].sizeThatFits(
                ProposedViewSize(width: fittedWidth, height: nil)
            )
            let needsWrap = !currentRow.items.isEmpty
                && currentRow.width + horizontalSpacing + fittedSize.width > availableWidth

            if needsWrap {
                rows.append(currentRow)
                currentRow = FlowRow()
            }

            currentRow.items.append(FlowRowItem(index: index, size: fittedSize))
            currentRow.width += currentRow.items.count == 1
                ? fittedSize.width
                : horizontalSpacing + fittedSize.width
            currentRow.height = max(currentRow.height, fittedSize.height)
        }

        if !currentRow.items.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }
}

private struct FlowRow {
    var items: [FlowRowItem] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
}

private struct FlowRowItem {
    let index: Int
    let size: CGSize
}

private struct CalendarGridWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CalendarWeekdayLabelWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct BlogTagStatisticItem: Identifiable {
    let tag: String
    let count: Int
    let style: BlogTagStatisticStyle

    var id: String {
        tag
    }

    var accessibilityID: String {
        tag.replacingOccurrences(of: " ", with: "-")
    }
}

private struct BlogTagStatisticStyle {
    let foreground: Color
    let fill: Color
    let stroke: Color
    let shadow: Color

    static func style(for index: Int) -> BlogTagStatisticStyle {
        presets[index % presets.count]
    }

    private static let presets: [BlogTagStatisticStyle] = [
        BlogTagStatisticStyle(
            foreground: Color(red: 0.23, green: 0.28, blue: 0.66),
            fill: Color(red: 0.93, green: 0.94, blue: 0.99),
            stroke: Color(red: 0.74, green: 0.77, blue: 0.96),
            shadow: Color(red: 0.23, green: 0.28, blue: 0.66).opacity(0.12)
        ),
        BlogTagStatisticStyle(
            foreground: Color(red: 0.63, green: 0.20, blue: 0.37),
            fill: Color(red: 0.98, green: 0.94, blue: 0.96),
            stroke: Color(red: 0.92, green: 0.77, blue: 0.83),
            shadow: Color(red: 0.63, green: 0.20, blue: 0.37).opacity(0.10)
        ),
        BlogTagStatisticStyle(
            foreground: Color(red: 0.20, green: 0.56, blue: 0.41),
            fill: Color(red: 0.92, green: 0.97, blue: 0.95),
            stroke: Color(red: 0.75, green: 0.90, blue: 0.83),
            shadow: Color(red: 0.20, green: 0.56, blue: 0.41).opacity(0.10)
        ),
        BlogTagStatisticStyle(
            foreground: Color(red: 0.89, green: 0.46, blue: 0.33),
            fill: Color(red: 1.00, green: 0.95, blue: 0.93),
            stroke: Color(red: 0.96, green: 0.82, blue: 0.76),
            shadow: Color(red: 0.89, green: 0.46, blue: 0.33).opacity(0.10)
        ),
        BlogTagStatisticStyle(
            foreground: Color(red: 0.38, green: 0.38, blue: 0.91),
            fill: Color(red: 0.94, green: 0.94, blue: 1.00),
            stroke: Color(red: 0.78, green: 0.79, blue: 0.98),
            shadow: Color(red: 0.38, green: 0.38, blue: 0.91).opacity(0.10)
        )
    ]
}
