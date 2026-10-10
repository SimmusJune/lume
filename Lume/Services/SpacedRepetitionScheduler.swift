import Foundation

/// Smart Review 的排程器。
///
/// 纯函数：输入候选池 + 各曲复习状态 + 当前时间，输出一次会话的播放顺序。
/// 排程分两步——
/// 1. **跨天**：把「今天到期」的曲目挑出来排到主线前面，越不熟、被跳过越多、逾期越久的越靠前。
/// 2. **会话内**：对主线里前 `interleaveHeadCount` 首且到期的曲目做递进间隔穿插，
///    让新歌在一次会话里出现 2~3 次，两次之间隔开若干首其他歌，且间隔逐步拉长。
///
/// 间隔会按池子大小自适应（见 `gaps(forOccurrences:spineLength:)`）：
/// 池子只有 4 首时「隔 2 首」等于隔一半，会把队列撑爆，所以间隔要跟着缩。
/// 主线走完后还没排上的重复项直接丢弃，不做「补位轮」——否则填充曲目会把
/// 已有重复项再推一轮，队列无限膨胀。
enum SpacedRepetitionScheduler {
    /// 单次会话里一首歌最多出现几次。
    static let maxOccurrences = 3
    /// 只有主线里前 N 首才做递进穿插，否则队列会无限膨胀。
    static let interleaveHeadCount = 6
    /// 出现 3 次时，第 2、3 次与上一次之间隔几首其他歌（上限，实际会按池子大小收缩）。
    static let firstPassGaps = [2, 4]
    /// 出现 2 次时的间隔（上限）。
    static let secondPassGap = 3

    // MARK: - 判定

    /// 没有任何记录（新歌）或没有到期时间，都当作「立即到期」。
    static func isDue(_ state: ReviewState?, now: Date) -> Bool {
        guard let state else { return true }
        guard let dueAt = state.dueAt else { return true }
        return dueAt <= now
    }

    /// 档位越低，一次会话里需要出现越多次。
    static func occurrences(forBox box: Int) -> Int {
        switch box {
        case ..<2: return 3
        case 2, 3: return 2
        default: return 1
        }
    }

    /// 把「出现次数」翻译成「每次之间隔几首歌」。
    ///
    /// 间隔上限是 [2, 4] / [3]，但主线本身不够长时按比例收缩，
    /// 否则重复项会被挤到主线之外、永远排不上。
    static func gaps(forOccurrences count: Int, spineLength: Int) -> [Int] {
        guard spineLength > 0 else { return [] }
        switch count {
        case 3...:
            let first = max(1, min(firstPassGaps[0], spineLength / 4))
            let second = max(first + 1, min(firstPassGaps[1], spineLength / 2))
            return [first, second]
        case 2:
            return [max(1, min(secondPassGap, spineLength / 3))]
        default:
            return []
        }
    }

    // MARK: - 排程

    static func buildQueue(pool: [String], states: [String: ReviewState], now: Date = Date()) -> [String] {
        var seen: Set<String> = []
        let uniquePool = pool.compactMap { raw -> String? in
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return id
        }
        guard !uniquePool.isEmpty else { return [] }

        let due = uniquePool.filter { isDue(states[$0], now: now) }
        let later = uniquePool.filter { !isDue(states[$0], now: now) }

        let orderedDue = due.sorted { lhs, rhs in
            let left = states[lhs]
            let right = states[rhs]
            // 越不熟越靠前；新歌（还没记录，记作 -1）直接排最前，趁孩子注意力最好的时候听新的
            let leftBox = left?.box ?? -1
            let rightBox = right?.box ?? -1
            if leftBox != rightBox { return leftBox < rightBox }
            // 被跳过越多越靠前
            let leftLapses = left?.lapseCount ?? 0
            let rightLapses = right?.lapseCount ?? 0
            if leftLapses != rightLapses { return leftLapses > rightLapses }
            // 逾期越久越靠前
            let leftDue = left?.dueAt ?? .distantPast
            let rightDue = right?.dueAt ?? .distantPast
            if leftDue != rightDue { return leftDue < rightDue }
            return lhs < rhs
        }

        let orderedLater = later.sorted { lhs, rhs in
            let leftBox = states[lhs]?.box ?? 0
            let rightBox = states[rhs]?.box ?? 0
            if leftBox != rightBox { return leftBox < rightBox }
            return lhs < rhs
        }

        return interleave(spine: orderedDue + orderedLater, states: states, now: now)
    }

    /// 把递进重复插进主线。
    ///
    /// 用「登记待插入项 + 每放一首歌替它倒数一格」的模拟来实现：
    /// 间隔 2 首意味着这首之后再放 2 首别的歌，才轮到它重复出现一次。
    private static func interleave(spine: [String], states: [String: ReviewState], now: Date) -> [String] {
        struct PendingRepeat {
            let song: String
            let gaps: [Int]
            var step: Int
            var remaining: Int
        }

        var order: [String] = []
        var pending: [PendingRepeat] = []

        func place(_ song: String) {
            order.append(song)

            for index in pending.indices {
                pending[index].remaining -= 1
            }

            var fired: [PendingRepeat] = []
            pending.removeAll { entry in
                guard entry.remaining <= 0 else { return false }
                fired.append(entry)
                return true
            }
            order.append(contentsOf: fired.map(\.song))

            for var entry in fired {
                entry.step += 1
                guard entry.step < entry.gaps.count else { continue }
                entry.remaining = entry.gaps[entry.step]
                pending.append(entry)
            }
        }

        for (index, song) in spine.enumerated() {
            place(song)

            guard index < interleaveHeadCount else { continue }
            let state = states[song]
            guard isDue(state, now: now) else { continue }
            let wanted = min(occurrences(forBox: state?.box ?? 0), maxOccurrences)
            let planned = gaps(forOccurrences: wanted, spineLength: spine.count)
            guard let first = planned.first else { continue }
            pending.append(PendingRepeat(song: song, gaps: planned, step: 0, remaining: first))
        }

        // 主线走完可能还剩没排上的重复项（池子越大越容易出现「间隔还没走完，歌已经放完了」）。
        // 这里直接补到队尾，而且**不再重新登记**——否则补进去的歌会再推出一轮重复，队列无限膨胀。
        // 上限一个池子的长度，保证补位不会喧宾夺主；同时跳过会跟上一位撞车的曲目，
        // 这样单曲池不会被排成「同一首连放两遍」。
        pending.sort { $0.remaining < $1.remaining }
        var tailBudget = spine.count
        while tailBudget > 0, !pending.isEmpty {
            guard let index = pending.firstIndex(where: { $0.song != order.last }) else { break }
            order.append(pending.remove(at: index).song)
            tailBudget -= 1
        }

        return order
    }
}
