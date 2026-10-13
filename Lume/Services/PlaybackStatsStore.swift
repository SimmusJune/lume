import Combine
import Foundation

struct DailyPlayback: Identifiable, Hashable {
    let id: String
    let date: Date
    let seconds: Int
}

/// 一次「完整播放」的记录：某首媒体在某个时刻被完整听完了一遍。
struct PlaybackEvent: Codable, Hashable, Sendable, Identifiable {
    let mediaID: String
    let date: Date

    var id: String { "\(mediaID)@\(date.timeIntervalSince1970)" }
}

/// 某首媒体的累计播放次数（用于排行）。
struct PlayedCount: Identifiable, Hashable, Sendable {
    let mediaID: String
    let count: Int

    var id: String { mediaID }
}

struct PlaybackStatsSnapshot: Codable, Hashable, Sendable {
    var totalSeconds: Int
    var dailySeconds: [String: Int]
    var playCounts: [String: Int]
    var history: [PlaybackEvent]

    nonisolated init(
        totalSeconds: Int,
        dailySeconds: [String: Int],
        playCounts: [String: Int] = [:],
        history: [PlaybackEvent] = []
    ) {
        self.totalSeconds = totalSeconds
        self.dailySeconds = dailySeconds
        self.playCounts = playCounts
        self.history = history
    }

    /// 兼容早期存档：老版本导出的 JSON 里没有 playCounts / history，缺省视为空。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalSeconds = (try? container.decode(Int.self, forKey: .totalSeconds)) ?? 0
        dailySeconds = (try? container.decode([String: Int].self, forKey: .dailySeconds)) ?? [:]
        playCounts = (try? container.decode([String: Int].self, forKey: .playCounts)) ?? [:]
        history = (try? container.decode([PlaybackEvent].self, forKey: .history)) ?? []
    }

    nonisolated var normalized: PlaybackStatsSnapshot {
        let cleanedDailySeconds = dailySeconds.reduce(into: [String: Int]()) { partialResult, entry in
            partialResult[entry.key] = max(0, entry.value)
        }
        let summedDailySeconds = cleanedDailySeconds.values.reduce(0, +)

        let cleanedPlayCounts = playCounts.reduce(into: [String: Int]()) { partialResult, entry in
            guard !entry.key.isEmpty, entry.value > 0 else { return }
            partialResult[entry.key] = entry.value
        }

        let cleanedHistory = history.filter { !$0.mediaID.isEmpty }

        return PlaybackStatsSnapshot(
            totalSeconds: max(max(0, totalSeconds), summedDailySeconds),
            dailySeconds: cleanedDailySeconds,
            playCounts: cleanedPlayCounts,
            history: cleanedHistory
        )
    }
}

enum PlaybackStatsStorage {
    nonisolated static let totalKey = "lume.playback.totalSeconds"
    nonisolated static let dailyKey = "lume.playback.dailySeconds"
    nonisolated static let playCountsKey = "lume.playback.playCounts"
    nonisolated static let historyKey = "lume.playback.history"

    nonisolated static func loadSnapshot(from defaults: UserDefaults = .standard, namespace: String? = nil) -> PlaybackStatsSnapshot {
        let totalSeconds = max(0, defaults.integer(forKey: key(totalKey, namespace: namespace)))

        let dailySeconds: [String: Int]
        if let data = defaults.data(forKey: key(dailyKey, namespace: namespace)),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            dailySeconds = decoded
        } else {
            dailySeconds = [:]
        }

        let playCounts: [String: Int]
        if let data = defaults.data(forKey: key(playCountsKey, namespace: namespace)),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            playCounts = decoded
        } else {
            playCounts = [:]
        }

        let history: [PlaybackEvent]
        if let data = defaults.data(forKey: key(historyKey, namespace: namespace)),
           let decoded = try? JSONDecoder().decode([PlaybackEvent].self, from: data) {
            history = decoded
        } else {
            history = []
        }

        return PlaybackStatsSnapshot(
            totalSeconds: totalSeconds,
            dailySeconds: dailySeconds,
            playCounts: playCounts,
            history: history
        ).normalized
    }

    nonisolated static func saveSnapshot(_ snapshot: PlaybackStatsSnapshot, to defaults: UserDefaults = .standard, namespace: String? = nil) {
        let normalized = snapshot.normalized
        defaults.set(normalized.totalSeconds, forKey: key(totalKey, namespace: namespace))
        if let data = try? JSONEncoder().encode(normalized.dailySeconds) {
            defaults.set(data, forKey: key(dailyKey, namespace: namespace))
        }
        if let data = try? JSONEncoder().encode(normalized.playCounts) {
            defaults.set(data, forKey: key(playCountsKey, namespace: namespace))
        }
        if let data = try? JSONEncoder().encode(normalized.history) {
            defaults.set(data, forKey: key(historyKey, namespace: namespace))
        }
    }

    nonisolated private static func key(_ base: String, namespace: String?) -> String {
        guard let namespace else { return base }
        return "lume.family.\(namespace).\(base)"
    }
}

@MainActor
final class PlaybackStatsStore: ObservableObject {
    static let shared = PlaybackStatsStore()

    /// 历史记录最多保留的天数与条数，避免 UserDefaults 无限膨胀。
    private static let historyMaxAgeDays = 7
    private static let historyMaxCount = 1000

    @Published private(set) var totalSeconds: Int
    @Published private(set) var dailySeconds: [String: Int]
    @Published private(set) var playCounts: [String: Int]
    @Published private(set) var history: [PlaybackEvent]

    private let defaults: UserDefaults
    private var localSnapshot: PlaybackStatsSnapshot
    private var namespace: String?
    private var remoteSnapshots: [String: PlaybackStatsSnapshot] = [:]

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
        self.localSnapshot = snapshot
        self.totalSeconds = snapshot.totalSeconds
        self.dailySeconds = snapshot.dailySeconds
        self.playCounts = snapshot.playCounts
        self.history = snapshot.history
    }

    // MARK: - 播放时长

    func recordPlayback(seconds: Int, at date: Date = Date()) {
        guard seconds > 0 else { return }
        localSnapshot.totalSeconds += seconds
        let key = Self.dateKey(for: date)
        localSnapshot.dailySeconds[key, default: 0] += seconds
        persist()
        publish()
        if namespace != nil { FamilySharingManager.shared.playbackDidChange() }
    }

    // MARK: - 完整播放（次数 + 历史）

    /// 一首歌完整播放一遍后调用：次数 +1，并往历史里追加一条记录。
    func recordCompletedPlayback(mediaID: String, at date: Date = Date()) {
        let id = mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        localSnapshot.playCounts[id, default: 0] += 1
        localSnapshot.history.append(PlaybackEvent(mediaID: id, date: date))
        trimHistory(relativeTo: date)
        persist()
        publish()
        if namespace != nil { FamilySharingManager.shared.playbackDidChange(immediate: true) }
    }

    func playCount(for mediaID: String) -> Int {
        playCounts[mediaID] ?? 0
    }

    var totalPlays: Int {
        playCounts.values.reduce(0, +)
    }

    /// 最近 `hours` 小时内的完整播放记录，按时间倒序。
    func recentHistory(hours: Int = 24, endingAt date: Date = Date()) -> [PlaybackEvent] {
        guard hours > 0 else { return [] }
        guard let cutoff = Calendar.current.date(byAdding: .hour, value: -hours, to: date) else { return [] }
        return history
            .filter { $0.date >= cutoff && $0.date <= date }
            .sorted { $0.date > $1.date }
    }

    /// 播放次数排行，次数相同的按 mediaID 稳定排序。
    func topPlayed(limit: Int = 20) -> [PlayedCount] {
        guard limit > 0 else { return [] }
        return playCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(limit)
            .map { PlayedCount(mediaID: $0.key, count: $0.value) }
    }

    // MARK: - 趋势

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
        localSnapshot = PlaybackStatsStorage.loadSnapshot(from: defaults, namespace: namespace)
        publish()
    }

    func activateFamily(id: String, copyPersonalStats: Bool) {
        namespace = id
        let marker = "lume.family.\(id).playback.initialized"
        if copyPersonalStats && !defaults.bool(forKey: marker) {
            PlaybackStatsStorage.saveSnapshot(localSnapshot, to: defaults, namespace: id)
        }
        defaults.set(true, forKey: marker)
        localSnapshot = PlaybackStatsStorage.loadSnapshot(from: defaults, namespace: id)
        remoteSnapshots = [:]
        publish()
    }

    func deactivateFamily() {
        namespace = nil
        remoteSnapshots = [:]
        reloadFromStorage()
    }

    func localFamilySnapshot() -> PlaybackStatsSnapshot {
        localSnapshot
    }

    func displayedSnapshot() -> PlaybackStatsSnapshot {
        PlaybackStatsSnapshot(totalSeconds: totalSeconds, dailySeconds: dailySeconds, playCounts: playCounts, history: history)
    }

    func applyRemoteFamilySnapshots(_ snapshots: [String: PlaybackStatsSnapshot], localDeviceID: String) {
        guard namespace != nil else { return }
        if let server = snapshots[localDeviceID] {
            var merged = localSnapshot
            merged.totalSeconds = max(merged.totalSeconds, server.totalSeconds)
            for (day, seconds) in server.dailySeconds {
                merged.dailySeconds[day] = max(merged.dailySeconds[day] ?? 0, seconds)
            }
            for (id, count) in server.playCounts {
                merged.playCounts[id] = max(merged.playCounts[id] ?? 0, count)
            }
            let historyByID = Dictionary(
                (merged.history + server.history).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            merged.history = Array(historyByID.values.sorted { $0.date < $1.date }.suffix(Self.historyMaxCount))
            if merged != localSnapshot {
                localSnapshot = merged
                persist()
            }
            if merged != server { FamilySharingManager.shared.playbackDidChange(immediate: true) }
        } else if localSnapshot.totalSeconds > 0 || !localSnapshot.playCounts.isEmpty {
            FamilySharingManager.shared.playbackDidChange(immediate: true)
        }
        remoteSnapshots = snapshots.filter { $0.key != localDeviceID }
        publish()
    }

    private func trimHistory(relativeTo date: Date) {
        let calendar = Calendar.current
        if let cutoff = calendar.date(byAdding: .day, value: -Self.historyMaxAgeDays, to: date) {
            localSnapshot.history.removeAll { $0.date < cutoff }
        }
        if localSnapshot.history.count > Self.historyMaxCount {
            localSnapshot.history.removeFirst(localSnapshot.history.count - Self.historyMaxCount)
        }
    }

    private func persist() {
        PlaybackStatsStorage.saveSnapshot(localSnapshot, to: defaults, namespace: namespace)
    }

    private func publish() {
        var aggregate = localSnapshot
        for snapshot in remoteSnapshots.values {
            aggregate.totalSeconds += snapshot.totalSeconds
            for (day, seconds) in snapshot.dailySeconds {
                aggregate.dailySeconds[day, default: 0] += seconds
            }
            for (id, count) in snapshot.playCounts {
                aggregate.playCounts[id, default: 0] += count
            }
            aggregate.history.append(contentsOf: snapshot.history)
        }
        totalSeconds = aggregate.totalSeconds
        dailySeconds = aggregate.dailySeconds
        playCounts = aggregate.playCounts
        history = Array(aggregate.history.sorted { $0.date < $1.date }.suffix(Self.historyMaxCount))
    }
}
