import Combine
import Foundation

struct DailyPlayback: Identifiable, Hashable {
    let id: String
    let date: Date
    let seconds: Int
}

struct PlaybackStatsSnapshot: Codable, Hashable, Sendable {
    let totalSeconds: Int
    let dailySeconds: [String: Int]

    nonisolated var normalized: PlaybackStatsSnapshot {
        let cleanedDailySeconds = dailySeconds.reduce(into: [String: Int]()) { partialResult, entry in
            partialResult[entry.key] = max(0, entry.value)
        }
        let summedDailySeconds = cleanedDailySeconds.values.reduce(0, +)
        return PlaybackStatsSnapshot(
            totalSeconds: max(max(0, totalSeconds), summedDailySeconds),
            dailySeconds: cleanedDailySeconds
        )
    }
}

enum PlaybackStatsStorage {
    nonisolated static let totalKey = "lume.playback.totalSeconds"
    nonisolated static let dailyKey = "lume.playback.dailySeconds"

    nonisolated static func loadSnapshot(from defaults: UserDefaults = .standard) -> PlaybackStatsSnapshot {
        let totalSeconds = max(0, defaults.integer(forKey: totalKey))
        let dailySeconds: [String: Int]
        if let data = defaults.data(forKey: dailyKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            dailySeconds = decoded
        } else {
            dailySeconds = [:]
        }
        return PlaybackStatsSnapshot(totalSeconds: totalSeconds, dailySeconds: dailySeconds).normalized
    }

    nonisolated static func saveSnapshot(_ snapshot: PlaybackStatsSnapshot, to defaults: UserDefaults = .standard) {
        let normalized = snapshot.normalized
        defaults.set(normalized.totalSeconds, forKey: totalKey)
        if let data = try? JSONEncoder().encode(normalized.dailySeconds) {
            defaults.set(data, forKey: dailyKey)
        }
    }
}

@MainActor
final class PlaybackStatsStore: ObservableObject {
    static let shared = PlaybackStatsStore()

    @Published private(set) var totalSeconds: Int
    @Published private(set) var dailySeconds: [String: Int]

    private let defaults: UserDefaults

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
        let snapshot = PlaybackStatsStorage.loadSnapshot(from: defaults)
        self.totalSeconds = snapshot.totalSeconds
        self.dailySeconds = snapshot.dailySeconds
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

    func reloadFromStorage() {
        let snapshot = PlaybackStatsStorage.loadSnapshot(from: defaults)
        totalSeconds = snapshot.totalSeconds
        dailySeconds = snapshot.dailySeconds
    }

    private func persist() {
        PlaybackStatsStorage.saveSnapshot(
            PlaybackStatsSnapshot(totalSeconds: totalSeconds, dailySeconds: dailySeconds),
            to: defaults
        )
    }
}
