import Combine
import Foundation

/// 一首曲目的复习状态（Smart Review 专用）。
///
/// 档位是 Leitner box 的简化版：0 = 刚接触，`ReviewIntervals.maxBox` = 已熟练。
/// 这里存的是「跨天」的掌握度；单次会话内的递进间隔由 `SpacedRepetitionScheduler`
/// 排队列时即时算，不落盘——两件事别混在一起。
struct ReviewState: Codable, Hashable, Sendable {
    /// 当前档位，0...`ReviewIntervals.maxBox`。
    var box: Int
    /// 最近一次完整播完的时间。
    var lastReviewedAt: Date?
    /// 下次到期复习的时间。为 nil 视为「立即到期」，也就是还没学过的新曲目。
    var dueAt: Date?
    /// 累计完整播完的次数。
    var completedCount: Int
    /// 中途被手动切走的次数。
    var lapseCount: Int

    init(
        box: Int = 0,
        lastReviewedAt: Date? = nil,
        dueAt: Date? = nil,
        completedCount: Int = 0,
        lapseCount: Int = 0
    ) {
        self.box = box
        self.lastReviewedAt = lastReviewedAt
        self.dueAt = dueAt
        self.completedCount = completedCount
        self.lapseCount = lapseCount
    }

    /// 兼容早期存档：以后再加字段照这个写法给默认值，别依赖合成的 decoder。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        box = (try? container.decode(Int.self, forKey: .box)) ?? 0
        lastReviewedAt = try? container.decode(Date.self, forKey: .lastReviewedAt)
        dueAt = try? container.decode(Date.self, forKey: .dueAt)
        completedCount = (try? container.decode(Int.self, forKey: .completedCount)) ?? 0
        lapseCount = (try? container.decode(Int.self, forKey: .lapseCount)) ?? 0
    }
}

/// 复习状态的落盘结构。
struct ReviewSnapshot: Codable, Hashable, Sendable {
    var states: [String: ReviewState]

    init(states: [String: ReviewState] = [:]) {
        self.states = states
    }

    /// 缺字段容错：老版本导出的 JSON 里没有 review_states，缺省视为空。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        states = (try? container.decode([String: ReviewState].self, forKey: .states)) ?? [:]
    }

    nonisolated var normalized: ReviewSnapshot {
        var cleaned: [String: ReviewState] = [:]
        for (key, value) in states {
            let id = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            var state = value
            state.box = min(max(0, state.box), ReviewIntervals.maxBox)
            state.completedCount = max(0, state.completedCount)
            state.lapseCount = max(0, state.lapseCount)
            cleaned[id] = state
        }
        return ReviewSnapshot(states: cleaned)
    }
}

/// 各档位对应的复习间隔（天），下标即档位。
enum ReviewIntervals {
    nonisolated static let days: [Int] = [1, 2, 4, 8, 16, 30]
    nonisolated static let maxBox = 5

    /// 升到 / 退到 `box` 档之后，隔多久再复习。
    nonisolated static func interval(forBox box: Int) -> TimeInterval {
        let clamped = min(max(0, box), maxBox)
        return TimeInterval(days[clamped]) * 24 * 60 * 60
    }
}

enum SpacedRepetitionStorage {
    nonisolated static let statesKey = "lume.review.states"

    nonisolated static func loadSnapshot(from defaults: UserDefaults = .standard) -> ReviewSnapshot {
        guard let data = defaults.data(forKey: statesKey),
              let decoded = try? JSONDecoder().decode(ReviewSnapshot.self, from: data) else {
            return ReviewSnapshot()
        }
        return decoded.normalized
    }

    nonisolated static func saveSnapshot(_ snapshot: ReviewSnapshot, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(snapshot.normalized) else { return }
        defaults.set(data, forKey: statesKey)
    }
}

@MainActor
final class SpacedRepetitionStore: ObservableObject {
    static let shared = SpacedRepetitionStore()

    /// 只保留最近仍在库里的曲目状态，避免删歌之后存档无限膨胀。
    private static let maxTrackedStates = 2000

    @Published private(set) var states: [String: ReviewState]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.states = SpacedRepetitionStorage.loadSnapshot(from: defaults).states
    }

    // MARK: - 读取

    /// 没记录过就返回一个「全新」状态（box 0、立即到期）。
    func state(for mediaID: String) -> ReviewState {
        states[mediaID] ?? ReviewState()
    }

    func isDue(mediaID: String, at date: Date = Date()) -> Bool {
        SpacedRepetitionScheduler.isDue(states[mediaID], now: date)
    }

    /// 已记录过的曲目里，当前到期的数量。
    func dueCount(at date: Date = Date()) -> Int {
        states.values.filter { state in
            guard let dueAt = state.dueAt else { return true }
            return dueAt <= date
        }.count
    }

    // MARK: - 写入

    /// 完整播完一遍 = 通过：进一档，按新档位重排下次到期时间。
    func recordCompleted(mediaID: String, at date: Date = Date()) {
        let id = mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        var state = states[id] ?? ReviewState()
        state.box = min(state.box + 1, ReviewIntervals.maxBox)
        state.lastReviewedAt = date
        state.completedCount += 1
        state.dueAt = date.addingTimeInterval(ReviewIntervals.interval(forBox: state.box))
        states[id] = state
        persist()
    }

    /// 中途被切走 = 没通过：退一档，并把到期时间拉近。
    func recordSkipped(mediaID: String, at date: Date = Date()) {
        let id = mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        var state = states[id] ?? ReviewState()
        state.box = max(state.box - 1, 0)
        state.lapseCount += 1
        state.dueAt = date.addingTimeInterval(ReviewIntervals.interval(forBox: state.box))
        states[id] = state
        persist()
    }

    /// 曲目被删除时清掉它的状态。
    func remove(mediaID: String) {
        guard states[mediaID] != nil else { return }
        states[mediaID] = nil
        persist()
    }

    func clearAll() {
        guard !states.isEmpty else { return }
        states = [:]
        persist()
    }

    // MARK: - 存档

    func reloadFromStorage() {
        states = SpacedRepetitionStorage.loadSnapshot(from: defaults).states
    }

    /// 导入时用。返回是否真的发生了变化。
    func importSnapshot(_ snapshot: ReviewSnapshot) -> Bool {
        let normalized = snapshot.normalized
        guard normalized.states != states else { return false }
        states = normalized.states
        persist()
        return true
    }

    private func persist() {
        if states.count > Self.maxTrackedStates {
            let trimmed = states
                .sorted { lhs, rhs in
                    let left = lhs.value.lastReviewedAt ?? .distantPast
                    let right = rhs.value.lastReviewedAt ?? .distantPast
                    if left != right { return left > right }
                    return lhs.key < rhs.key
                }
                .prefix(Self.maxTrackedStates)
            states = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0.value) })
        }
        SpacedRepetitionStorage.saveSnapshot(ReviewSnapshot(states: states), to: defaults)
    }
}
