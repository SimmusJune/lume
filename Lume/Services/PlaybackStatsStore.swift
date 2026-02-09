import Combine
import Foundation

struct DailyPlayback: Identifiable, Hashable {
    let id: String
    let date: Date
    let seconds: Int
}

@MainActor
final class PlaybackStatsStore: ObservableObject {
    static let shared = PlaybackStatsStore()

    @Published private(set) var totalSeconds: Int
    @Published private(set) var dailySeconds: [String: Int]

    private let defaults: UserDefaults
    private let totalKey = "lume.playback.totalSeconds"
    private let dailyKey = "lume.playback.dailySeconds"

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.totalSeconds = defaults.integer(forKey: totalKey)
        if let data = defaults.data(forKey: dailyKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.dailySeconds = decoded
        } else {
            self.dailySeconds = [:]
        }
    }

    func recordPlayback(seconds: Int, at date: Date = Date()) {
        guard seconds > 0 else { return }
        totalSeconds += seconds
        let key = Self.dateKey(for: date)
        dailySeconds[key, default: 0] += seconds
        persist()
    }

    func dailyTrend(days: Int, endingAt date: Date = Date()) -> [DailyPlayback] {
        guard days > 0 else { return [] }
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: date)
        var items: [DailyPlayback] = []
        items.reserveCapacity(days)
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else { continue }
            let key = Self.dateKey(for: day)
            let seconds = dailySeconds[key] ?? 0
            items.append(DailyPlayback(id: key, date: day, seconds: seconds))
        }
        return items
    }

    func monthlyTotals(for year: Int) -> [Int: Int] {
        var totals: [Int: Int] = [:]
        let calendar = Calendar.current
        for (key, seconds) in dailySeconds {
            guard let date = Self.dateFromKey(key) else { continue }
            let components = calendar.dateComponents([.year, .month], from: date)
            guard components.year == year, let month = components.month else { continue }
            totals[month, default: 0] += seconds
        }
        return totals
    }

    func yearlyTotals() -> [Int: Int] {
        var totals: [Int: Int] = [:]
        let calendar = Calendar.current
        for (key, seconds) in dailySeconds {
            guard let date = Self.dateFromKey(key) else { continue }
            let year = calendar.component(.year, from: date)
            totals[year, default: 0] += seconds
        }
        return totals
    }

    static func dateKey(for date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }

    static func dateFromKey(_ key: String) -> Date? {
        dayKeyFormatter.date(from: key)
    }

    private func persist() {
        defaults.set(totalSeconds, forKey: totalKey)
        if let data = try? JSONEncoder().encode(dailySeconds) {
            defaults.set(data, forKey: dailyKey)
        }
    }
}
