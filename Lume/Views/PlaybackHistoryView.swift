import SwiftUI

/// 历史播放页：展示最近 24 小时的完整播放记录，以及全库的播放次数排行。
struct PlaybackHistoryView: View {
    @EnvironmentObject private var playback: PlayerViewModel
    @ObservedObject private var stats = PlaybackStatsStore.shared

    @State private var itemsByID: [String: MediaItem] = [:]
    @State private var isLoading = true
    @State private var loadError: String?

    private let recentHours = 24
    private let topPlayedLimit = 20

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(hex: "0f1216"), Color(hex: "0b0d10")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCard
                    recentSection
                    topPlayedSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if itemsByID.isEmpty { await loadMedia() }
        }
        .onReceive(NotificationCenter.default.publisher(for: APIClient.didUpdateMedia)) { _ in
            Task { await loadMedia() }
        }
        .onReceive(NotificationCenter.default.publisher(for: APIClient.didDeleteMedia)) { _ in
            Task { await loadMedia() }
        }
    }

    // MARK: - 概览

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Play Count")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))

            Text("\(stats.totalPlays)")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Text(recentSummaryText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "9aa3ab"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(cardBackground)
    }

    private var recentSummaryText: String {
        let plays = recentEvents.count
        if plays == 0 {
            return "No full plays in the last 24 hours"
        }
        return "\(plays) full \(plays == 1 ? "play" : "plays") in the last 24 hours"
    }

    // MARK: - 最近一天的播放记录

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 24 Hours")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else if let loadError {
                Text(loadError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            } else if recentEvents.isEmpty {
                Text("Nothing played yet. Finish a track and it will show up here.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "9aa3ab"))
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(recentGroups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.5))

                            ForEach(group.events) { event in
                                if let item = itemsByID[event.mediaID] {
                                    HistoryPlayRow(
                                        item: item,
                                        timeText: timeText(event.date),
                                        playCount: stats.playCount(for: event.mediaID),
                                        showsCount: false
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        play(mediaID: event.mediaID, playlist: recentPlaylist)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(cardBackground)
    }

    // MARK: - 播放次数排行

    private var topPlayedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most Played")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else if topPlayedEntries.isEmpty {
                Text("No play counts yet.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "9aa3ab"))
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(topPlayedEntries.enumerated()), id: \.element.mediaID) { index, entry in
                        HistoryPlayRow(
                            item: entry.item,
                            timeText: nil,
                            playCount: entry.count,
                            showsCount: true,
                            rank: index + 1
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            play(mediaID: entry.mediaID, playlist: topPlayedPlaylist)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(cardBackground)
    }

    // MARK: - 数据

    private var recentEvents: [PlaybackEvent] {
        stats.recentHistory(hours: recentHours).filter { itemsByID[$0.mediaID] != nil }
    }

    private var recentGroups: [(title: String, events: [PlaybackEvent])] {
        var order: [String] = []
        var buckets: [String: [PlaybackEvent]] = [:]
        for event in recentEvents {
            let key = PlaybackStatsStore.dateKey(for: event.date)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(event)
        }
        return order.map { key in
            (title: dayTitle(forKey: key), events: buckets[key] ?? [])
        }
    }

    private var topPlayedEntries: [(mediaID: String, item: MediaItem, count: Int)] {
        stats.topPlayed(limit: topPlayedLimit).compactMap { entry in
            guard let item = itemsByID[entry.mediaID] else { return nil }
            return (mediaID: entry.mediaID, item: item, count: entry.count)
        }
    }

    private var recentPlaylist: [String] {
        var seen: Set<String> = []
        var ids: [String] = []
        for event in recentEvents where !seen.contains(event.mediaID) {
            seen.insert(event.mediaID)
            ids.append(event.mediaID)
        }
        return ids
    }

    private var topPlayedPlaylist: [String] {
        topPlayedEntries.map(\.mediaID)
    }

    private func loadMedia() async {
        do {
            let response = try await APIClient.shared.fetchMediaList(type: nil, keyword: nil)
            await MainActor.run {
                itemsByID = Dictionary(uniqueKeysWithValues: response.items.map { ($0.id, $0) })
                loadError = nil
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = "Failed to load library."
                isLoading = false
            }
        }
    }

    private func play(mediaID: String, playlist: [String]) {
        let queue = playlist.isEmpty ? [mediaID] : playlist
        playback.setQueue(ids: queue, currentID: mediaID, origin: .library)
        Task {
            await playback.load(id: mediaID, autoPlay: true)
            playback.isMiniVisible = true
            playback.presentExpanded = false
        }
    }

    // MARK: - 文案

    private func dayTitle(forKey key: String) -> String {
        let todayKey = PlaybackStatsStore.dateKey(for: Date())
        if key == todayKey { return "Today" }
        guard let date = PlaybackStatsStore.dateFromKey(key) else { return key }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

/// 历史 / 排行里的一行：封面 + 标题 + 时间或次数。
private struct HistoryPlayRow: View {
    let item: MediaItem
    let timeText: String?
    let playCount: Int
    let showsCount: Bool
    var rank: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 20, alignment: .center)
            }

            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let timeText {
                        Text(timeText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                    } else {
                        Text(item.type == .audio ? "Music" : "Video")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }

                    if showsCount {
                        Text("·")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.4))

                        HStack(spacing: 3) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(playCount)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color(hex: "9dff85"))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(0.08))
                .frame(width: 44, height: 44)

            CachedAsyncImage(url: item.thumbURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(systemName: item.type == .audio ? "music.note" : "film")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }
}

#Preview {
    NavigationStack {
        PlaybackHistoryView()
    }
    .environmentObject(PlayerViewModel())
}
