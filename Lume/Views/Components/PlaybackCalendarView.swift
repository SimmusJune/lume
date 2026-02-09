import SwiftUI

enum PlaybackStatsRange: String, CaseIterable {
    case day = "日"
    case month = "月"
    case year = "年"
}

struct PlaybackCalendarView: View {
    @Binding var month: Date
    let dailySeconds: [String: Int]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            weekHeader
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(buildDays()) { day in
                    CalendarDayCell(day: day, seconds: seconds(for: day.date))
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                month = shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text(monthTitle(month))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Button {
                month = shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var weekHeader: some View {
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        return HStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func buildDays() -> [CalendarDay] {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let weekday = calendar.component(.weekday, from: startOfMonth)
        let leadingEmpty = max(weekday - calendar.firstWeekday, 0)
        let daysInMonth = calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30

        var days: [CalendarDay] = []
        days.reserveCapacity(leadingEmpty + daysInMonth)
        for _ in 0..<leadingEmpty {
            days.append(CalendarDay.empty)
        }
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(CalendarDay(date: date))
            }
        }
        return days
    }

    private func seconds(for date: Date?) -> Int {
        guard let date else { return 0 }
        let key = PlaybackStatsStore.dateKey(for: date)
        return dailySeconds[key] ?? 0
    }

    private func shiftMonth(by value: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: date)
    }
}

private struct CalendarDay: Identifiable, Hashable {
    let id = UUID()
    let date: Date?

    static let empty = CalendarDay(date: nil)
}

private struct CalendarDayCell: View {
    let day: CalendarDay
    let seconds: Int

    private var isToday: Bool {
        guard let date = day.date else { return false }
        return Calendar.current.isDateInToday(date)
    }

    var body: some View {
        VStack(spacing: 4) {
            if let date = day.date {
                Text(dayNumber(from: date))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isToday ? Color(hex: "9dff85") : Color.white.opacity(0.85))

                Text(valueText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(valueColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(valueBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .overlay(alignment: .topTrailing) {
            if isToday {
                Text("今")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: "0b0d10"))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(hex: "9dff85"))
                    .clipShape(Capsule())
                    .offset(x: 4, y: -6)
            }
        }
    }

    private var valueText: String {
        let text = shortDurationText(seconds)
        return text.isEmpty ? "—" : text
    }

    private var valueColor: Color {
        seconds > 0 ? Color(hex: "68d19b") : Color.white.opacity(0.35)
    }

    private var valueBackground: Color {
        seconds > 0 ? Color(hex: "9dff85").opacity(0.18) : Color.white.opacity(0.04)
    }

    private func dayNumber(from date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return "\(day)"
    }

    private func shortDurationText(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let hours = Double(seconds) / 3600.0
        if hours >= 10 {
            return String(format: "%.0fh", hours)
        }
        if hours >= 1 {
            return String(format: "%.1fh", hours)
        }
        let minutes = max(1, seconds / 60)
        return "\(minutes)m"
    }
}

#Preview {
    PlaybackCalendarView(
        month: .constant(Date()),
        dailySeconds: [
            PlaybackStatsStore.dateKey(for: Date()): 1200
        ]
    )
}

struct PlaybackStatsRangePicker: View {
    @Binding var range: PlaybackStatsRange

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PlaybackStatsRange.allCases, id: \.self) { option in
                Button {
                    range = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(range == option ? Color(hex: "0b0d10") : Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(range == option ? Color.white : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
        )
    }
}

struct PlaybackMonthGridView: View {
    @Binding var year: Date
    let monthlySeconds: [Int: Int]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(1...12, id: \.self) { month in
                    PlaybackSummaryCell(
                        title: monthTitle(month),
                        seconds: monthlySeconds[month] ?? 0,
                        isAccent: isCurrentMonth(month)
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                year = shiftYear(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text(yearTitle(year))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Button {
                year = shiftYear(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func shiftYear(by value: Int) -> Date {
        Calendar.current.date(byAdding: .year, value: value, to: year) ?? year
    }

    private func yearTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年"
        return formatter.string(from: date)
    }

    private func monthTitle(_ month: Int) -> String {
        if isCurrentMonth(month) {
            return "本月"
        }
        return "\(month)月"
    }

    private func isCurrentMonth(_ month: Int) -> Bool {
        let calendar = Calendar.current
        let current = Date()
        let currentYear = calendar.component(.year, from: current)
        let currentMonth = calendar.component(.month, from: current)
        let selectedYear = calendar.component(.year, from: year)
        return currentYear == selectedYear && currentMonth == month
    }
}

struct PlaybackYearGridView: View {
    @Binding var pageEndYear: Int
    let yearlySeconds: [Int: Int]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        let currentYear = Calendar.current.component(.year, from: Date())
        let endYear = min(pageEndYear, currentYear)
        let startYear = endYear - 8
        let years = Array(startYear...endYear)

        return VStack(alignment: .leading, spacing: 12) {
            header(startYear: startYear, endYear: endYear, maxYear: currentYear)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(years, id: \.self) { year in
                    PlaybackSummaryCell(
                        title: yearTitle(year, currentYear: currentYear),
                        seconds: yearlySeconds[year] ?? 0,
                        isAccent: year == currentYear
                    )
                }
            }
        }
    }

    private func header(startYear: Int, endYear: Int, maxYear: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                pageEndYear -= 9
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text("\(startYear)-\(endYear)年")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Button {
                pageEndYear = min(maxYear, pageEndYear + 9)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(pageEndYear >= maxYear)
            .opacity(pageEndYear >= maxYear ? 0.4 : 1)
        }
    }

    private func yearTitle(_ year: Int, currentYear: Int) -> String {
        if year == currentYear {
            return "本年"
        }
        return "\(year)年"
    }
}

private struct PlaybackSummaryCell: View {
    let title: String
    let seconds: Int
    let isAccent: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))

            Text(summaryDurationText(seconds))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .padding(.vertical, 8)
        .background(valueBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var valueColor: Color {
        seconds > 0 ? Color(hex: "68d19b") : Color.white.opacity(0.45)
    }

    private var valueBackground: Color {
        if isAccent {
            return Color(hex: "9dff85").opacity(0.18)
        }
        if seconds > 0 {
            return Color(hex: "68d19b").opacity(0.18)
        }
        return Color.white.opacity(0.04)
    }
}

private func summaryDurationText(_ seconds: Int) -> String {
    guard seconds > 0 else { return "—" }
    let hours = Double(seconds) / 3600.0
    if hours >= 100 {
        return String(format: "%.0fh", hours)
    }
    if hours >= 10 {
        return String(format: "%.1fh", hours)
    }
    if hours >= 1 {
        return String(format: "%.2fh", hours)
    }
    let minutes = max(1, seconds / 60)
    return "\(minutes)m"
}
