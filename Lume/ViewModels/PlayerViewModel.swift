import AVFoundation
import Foundation
import Combine
import MediaPlayer
import SwiftUI

@MainActor
final class PlayerViewModel: ObservableObject {
    enum DeleteCurrentResult {
        case advancedToNext
        case queueEnded
    }

    enum PlayMode: String, CaseIterable {
        case sequential
        case singleLoop
        case shuffle

        var iconName: String {
            switch self {
            case .sequential: return "repeat"
            case .singleLoop: return "repeat.1"
            case .shuffle: return "shuffle"
            }
        }

        var label: String {
            switch self {
            case .sequential: return "Repeat All"
            case .singleLoop: return "Repeat One"
            case .shuffle: return "Shuffle"
            }
        }
    }

    enum PlayOrigin: Equatable {
        case favorites(name: String?)
        case playlist(name: String?)
        case library
        case unknown

        var label: String {
            switch self {
            case .favorites(let name):
                return format(prefix: "From Favorites", name: name)
            case .playlist(let name):
                return format(prefix: "From Playlist", name: name)
            case .library:
                return "From Library"
            case .unknown:
                return "Now Playing"
            }
        }

        private func format(prefix: String, name: String?) -> String {
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                return prefix
            }
            return "\(prefix) · \(trimmed)"
        }
    }

    @Published var player = AVPlayer()
    @Published var detail: MediaDetail?
    @Published var isPlaying = false
    @Published var positionSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var rate: Float = 1.0
    @Published var errorMessage: String?
    @Published var isMiniVisible = false
    @Published var presentExpanded = false
    @Published var playMode: PlayMode = .sequential {
        didSet {
            guard oldValue != playMode else { return }
            storedPlayMode = playMode.rawValue
        }
    }
    @Published private(set) var playOrigin: PlayOrigin = .unknown
    @Published private(set) var queueDetails: [MediaDetail] = []

    @AppStorage("lume.lastPlayedMediaID") private var lastPlayedMediaID = ""
    @AppStorage("lume.lastPlayedQueue") private var lastPlayedQueue = ""
    @AppStorage("lume.lastPlayedOriginType") private var lastPlayedOriginType = ""
    @AppStorage("lume.lastPlayedOriginName") private var lastPlayedOriginName = ""
    @AppStorage("lume.playMode") private var storedPlayMode = PlayMode.sequential.rawValue

    private let api: APIClient
    private var timeObserver: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var itemDurationObserver: NSKeyValueObservation?
    private var itemDidFinishObserver: NSObjectProtocol?
    private var lastProgressSentAt: Double = 0
    private var lastStatsPosition: Double = 0
    private var pendingStatsSeconds: Double = 0
    private var currentMediaID: String?
    @Published private(set) var playlist: [String] = []
    private var remoteConfigured = false
    private let statsStore = PlaybackStatsStore.shared
    private var queueLoadTask: Task<Void, Never>?
    private var isAdvancingTrack = false

    /// 当前曲在队列中的位置。以 mediaID 动态推导，而不是单独维护一份 index，
    /// 这样队列重建、曲目被删除后都不会出现下标与当前曲对不上的情况。
    private var currentIndex: Int? {
        guard let currentMediaID else { return nil }
        return playlist.firstIndex(of: currentMediaID)
    }

    /// 随机播放当前这一轮剩下的曲目。每轮是整个队列的一个随机排列，
    /// 放完（抽空）才洗下一轮。
    private var shuffleRemaining: [String] = []
    /// 洗这一轮时的队列快照，队列一变（重新 setQueue、删歌）就作废重洗。
    private var shufflePoolSignature: [String] = []

    init(api: APIClient = .shared) {
        self.api = api
        if let restoredMode = PlayMode(rawValue: storedPlayMode) {
            playMode = restoredMode
        }
        configureRemoteCommands()
    }

    func setQueue(ids: [String], currentID: String, origin: PlayOrigin = .unknown) {
        // 队列或起点曲变化 = 新的播放会话，随机播放重新开一轮；
        // 只是重新进播放页（同一个队列、同一首）则保留已抽过的池子。
        let isNewSession = playlist != ids || currentMediaID != currentID
        playlist = ids
        playOrigin = origin
        persistOrigin(origin)
        persistQueue(ids)
        loadQueueDetails(ids)
        if isNewSession {
            resetShufflePool()
        }
    }

    func load(id: String, autoPlay: Bool) async {
        errorMessage = nil
        if currentMediaID == id, detail != nil {
            if autoPlay {
                if durationSeconds > 0, positionSeconds >= max(0, durationSeconds - 0.5) {
                    seek(to: 0)
                }
                play()
                if let detail {
                    NowPlayingManager.updateMetadata(detail: detail, elapsed: positionSeconds, duration: durationSeconds, isPlaying: true)
                }
            }
            return
        }
        do {
            AudioSessionManager.configurePlayback()
            let detail = try await api.fetchMediaDetail(id: id)
            self.detail = detail
            currentMediaID = id
            lastPlayedMediaID = id
            let source = pickSource(from: detail.sources)
            let playbackURL = await AudioCache.shared.cachedURLIfNeeded(
                source: source,
                mediaType: detail.type,
                mediaID: detail.id
            )
            let item = AVPlayerItem(url: playbackURL)
            player.replaceCurrentItem(with: item)
            durationSeconds = Double(detail.durationMS) / 1000.0
            observePlayer(item: item)
            NowPlayingManager.updateMetadata(detail: detail, elapsed: 0, duration: durationSeconds, isPlaying: autoPlay)
            if autoPlay {
                play()
            }
        } catch {
            errorMessage = "Failed to load media."
        }
    }

    func restoreLastPlayedIfNeeded(autoPlay: Bool = false) async {
        let id = lastPlayedMediaID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        guard detail == nil else { return }
        if let queue = restoreQueue(), queue.contains(id) {
            setQueue(ids: queue, currentID: id, origin: restoreOrigin())
        }
        await load(id: id, autoPlay: autoPlay)
    }

    func playFromQueue(id: String) {
        guard playlist.contains(id) else { return }
        Task { await load(id: id, autoPlay: true) }
    }

    /// 正在播的这首被改了标题 / 副标题 / 标签后，刷新详情与队列缓存，
    /// 免得播放页、锁屏信息还显示旧名字。
    func refreshDetailIfNeeded(id: String) async {
        guard currentMediaID == id else { return }
        guard let updated = try? await api.fetchMediaDetail(id: id) else { return }

        detail = updated
        if updated.durationMS > 0 {
            durationSeconds = Double(updated.durationMS) / 1000.0
        }
        NowPlayingManager.updateMetadata(
            detail: updated,
            elapsed: positionSeconds,
            duration: durationSeconds,
            isPlaying: isPlaying
        )
        loadQueueDetails(playlist)
    }

    func togglePlay() {
        if isPlaying {
            pause()
            NowPlayingManager.updatePlayback(elapsed: positionSeconds, duration: durationSeconds, isPlaying: false)
            Task { await sendProgress(event: "pause") }
        } else {
            play()
            NowPlayingManager.updatePlayback(elapsed: positionSeconds, duration: durationSeconds, isPlaying: true)
        }
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time)
        lastStatsPosition = seconds
        NowPlayingManager.updatePlayback(elapsed: seconds, duration: durationSeconds, isPlaying: isPlaying)
    }

    func seek(by delta: Double) {
        let next = max(0, min(durationSeconds, positionSeconds + delta))
        seek(to: next)
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        if isPlaying {
            player.rate = newRate
        }
    }

    func teardown() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        itemStatusObserver = nil
        itemDurationObserver = nil
        if let itemDidFinishObserver {
            NotificationCenter.default.removeObserver(itemDidFinishObserver)
            self.itemDidFinishObserver = nil
        }
    }

    func nextTrack() {
        advanceTrack(auto: false)
    }

    func previousTrack() {
        if positionSeconds > 3 {
            seek(to: 0)
            return
        }
        guard let index = currentIndex else { return }
        let prevIndex = index - 1
        guard prevIndex >= 0 else { return }
        Task { await load(id: playlist[prevIndex], autoPlay: true) }
    }

    func deleteCurrentMedia() async throws -> DeleteCurrentResult {
        guard let detail else { throw APIError.httpStatus(404) }

        let deletedID = detail.id
        let nextID = nextTrackIDAfterDeletingCurrent(id: deletedID)

        try await api.deleteMedia(id: deletedID)
        removeFromQueue(id: deletedID)

        if let nextID {
            await load(id: nextID, autoPlay: true)
            guard currentMediaID == nextID else {
                clearPlaybackState()
                return .queueEnded
            }
            return .advancedToNext
        }

        clearPlaybackState()
        return .queueEnded
    }

    func play() {
        AudioSessionManager.configurePlayback()
        player.playImmediately(atRate: rate)
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func collapseToMini() {
        guard detail != nil else { return }
        isMiniVisible = true
        presentExpanded = false
    }

    private func configureRemoteCommands() {
        guard !remoteConfigured else { return }
        remoteConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlay()
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextTrack()
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousTrack()
            return .success
        }
    }

    private func pickSource(from sources: [MediaSource]) -> MediaSource {
        if let hls = sources.first(where: { $0.format.lowercased() == "m3u8" }) {
            return hls
        }
        if let mp4 = sources.first(where: { $0.format.lowercased() == "mp4" }) {
            return mp4
        }
        return sources[0]
    }

    private func observePlayer(item: AVPlayerItem) {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        itemStatusObserver = nil
        itemDurationObserver = nil
        if let itemDidFinishObserver {
            NotificationCenter.default.removeObserver(itemDidFinishObserver)
            self.itemDidFinishObserver = nil
        }
        lastStatsPosition = 0
        pendingStatsSeconds = 0

        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            positionSeconds = time.seconds
            updateDurationIfNeeded(from: item)
            recordPlaybackStats(currentPosition: time.seconds)
            maybeSendProgress()
        }

        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            if item.status == .readyToPlay {
                updateDurationIfNeeded(from: item)
            }
        }

        itemDurationObserver = item.observe(\.duration, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            updateDurationIfNeeded(from: item)
        }

        itemDidFinishObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let finishedItem = notification.object as? AVPlayerItem else { return }
            self.itemDidFinish(finishedItem)
        }
    }

    private func updateDurationIfNeeded(from item: AVPlayerItem) {
        let duration = item.duration
        guard duration.isNumeric else { return }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return }
        if abs(durationSeconds - seconds) > 0.5 {
            durationSeconds = seconds
            NowPlayingManager.updatePlayback(elapsed: positionSeconds, duration: durationSeconds, isPlaying: isPlaying)
        }
    }

    private func itemDidFinish(_ item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        isPlaying = false
        NowPlayingManager.updatePlayback(elapsed: durationSeconds, duration: durationSeconds, isPlaying: false)
        Task { await sendProgress(event: "end") }
        advanceTrack(auto: true)
    }

    private func maybeSendProgress() {
        let now = positionSeconds
        if now - lastProgressSentAt >= 5 {
            lastProgressSentAt = now
            Task { await sendProgress(event: nil) }
        }
        NowPlayingManager.updatePlayback(elapsed: now, duration: durationSeconds, isPlaying: isPlaying)
    }

    private func recordPlaybackStats(currentPosition: Double) {
        guard isPlaying else {
            lastStatsPosition = currentPosition
            return
        }
        let delta = currentPosition - lastStatsPosition
        lastStatsPosition = currentPosition
        guard delta > 0 else { return }
        if delta > 3 {
            return
        }
        pendingStatsSeconds += delta
        let wholeSeconds = Int(pendingStatsSeconds)
        guard wholeSeconds > 0 else { return }
        pendingStatsSeconds -= Double(wholeSeconds)
        statsStore.recordPlayback(seconds: wholeSeconds)
    }

    private func sendProgress(event: String?) async {
        guard let detail else { return }
        let positionMS = Int(positionSeconds * 1000)
        do {
            try await api.postProgress(id: detail.id, positionMS: positionMS, event: event)
        } catch {
            // Best-effort progress update; ignore failures.
        }
    }

    func cyclePlayMode() {
        let modes = PlayMode.allCases
        guard let index = modes.firstIndex(of: playMode) else { return }
        let nextIndex = (index + 1) % modes.count
        playMode = modes[nextIndex]
    }

    private func advanceTrack(auto: Bool) {
        guard !playlist.isEmpty else { return }
        guard !isAdvancingTrack else { return }
        guard let currentID = currentMediaID else { return }
        isAdvancingTrack = true

        if playMode == .singleLoop, auto {
            restartCurrentTrack()
            return
        }

        if playMode == .shuffle {
            guard let nextID = nextShuffleID(excluding: currentID) else {
                isAdvancingTrack = false
                return
            }
            loadAdvancingTrack(id: nextID)
            return
        }

        let nextIndex: Int
        if let index = playlist.firstIndex(of: currentID) {
            let candidate = index + 1
            nextIndex = candidate < playlist.count ? candidate : 0
        } else {
            nextIndex = 0
        }
        loadAdvancingTrack(id: playlist[nextIndex])
    }

    private func loadAdvancingTrack(id: String) {
        Task { [weak self] in
            guard let self else { return }
            defer { isAdvancingTrack = false }
            await load(id: id, autoPlay: true)
        }
    }

    private func restartCurrentTrack() {
        let targetDuration = durationSeconds
        let restartTime = CMTime(seconds: 0, preferredTimescale: 600)
        player.seek(to: restartTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            positionSeconds = 0
            lastStatsPosition = 0
            pendingStatsSeconds = 0
            play()
            NowPlayingManager.updatePlayback(
                elapsed: 0,
                duration: targetDuration,
                isPlaying: true
            )
            isAdvancingTrack = false
        }
    }

    /// 真正的随机播放：每轮把整个队列洗牌成一个排列，按顺序放完再洗下一轮，
    /// 所以一轮之内每首歌只会出现一次（而不是随机跳转造成的反复横跳）。
    private func nextShuffleID(excluding currentID: String) -> String? {
        guard !playlist.isEmpty else { return nil }

        // 队列变了（重新 setQueue、删歌等）就作废当前这轮，重新洗。
        if shufflePoolSignature != playlist {
            shufflePoolSignature = playlist
            shuffleRemaining = []
        }

        // 一轮放完 → 洗下一轮。池子是从末尾取的，所以保证新一轮第一首
        // 不是刚播完的那首，避免跨轮处出现连续重复。
        if shuffleRemaining.isEmpty {
            shuffleRemaining = playlist.shuffled()
            if shuffleRemaining.count > 1, shuffleRemaining.last == currentID {
                let swapIndex = Int.random(in: 0..<(shuffleRemaining.count - 1))
                shuffleRemaining.swapAt(swapIndex, shuffleRemaining.count - 1)
            }
        }

        return shuffleRemaining.popLast()
    }

    private func resetShufflePool() {
        shuffleRemaining = []
        shufflePoolSignature = []
    }

    private func loadQueueDetails(_ ids: [String]) {
        queueLoadTask?.cancel()
        guard !ids.isEmpty else {
            queueDetails = []
            return
        }
        let snapshot = ids
        queueLoadTask = Task { [weak self] in
            guard let self else { return }
            var details: [MediaDetail] = []
            for id in snapshot {
                if Task.isCancelled { return }
                if let detail = try? await api.fetchMediaDetail(id: id) {
                    details.append(detail)
                }
            }
            if Task.isCancelled { return }
            queueDetails = details
        }
    }

    private func persistQueue(_ ids: [String]) {
        guard !ids.isEmpty else {
            lastPlayedQueue = ""
            return
        }
        if let data = try? JSONEncoder().encode(ids) {
            lastPlayedQueue = String(data: data, encoding: .utf8) ?? ""
        }
    }

    private func persistOrigin(_ origin: PlayOrigin) {
        switch origin {
        case .favorites(let name):
            lastPlayedOriginType = "favorites"
            lastPlayedOriginName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .playlist(let name):
            lastPlayedOriginType = "playlist"
            lastPlayedOriginName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .library:
            lastPlayedOriginType = "library"
            lastPlayedOriginName = ""
        case .unknown:
            lastPlayedOriginType = ""
            lastPlayedOriginName = ""
        }
    }

    private func restoreOrigin() -> PlayOrigin {
        let trimmedName = lastPlayedOriginName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String? = trimmedName.isEmpty ? nil : trimmedName
        switch lastPlayedOriginType {
        case "favorites":
            return .favorites(name: name)
        case "playlist":
            return .playlist(name: name)
        case "library":
            return .library
        default:
            return .unknown
        }
    }

    private func restoreQueue() -> [String]? {
        let trimmed = lastPlayedQueue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    private func nextTrackIDAfterDeletingCurrent(id: String) -> String? {
        guard !playlist.isEmpty else { return nil }

        guard let index = playlist.firstIndex(of: id) else {
            return playlist.first(where: { $0 != id })
        }
        guard playlist.count > 1 else { return nil }
        let nextIndex = index + 1 < playlist.count ? index + 1 : 0
        return playlist[nextIndex]
    }

    private func removeFromQueue(id: String) {
        let updatedPlaylist = playlist.filter { $0 != id }
        playlist = updatedPlaylist
        persistQueue(updatedPlaylist)
        loadQueueDetails(updatedPlaylist)
    }

    private func clearPlaybackState() {
        teardown()
        queueLoadTask?.cancel()
        pause()
        player.replaceCurrentItem(with: nil)
        detail = nil
        currentMediaID = nil
        positionSeconds = 0
        durationSeconds = 0
        errorMessage = nil
        queueDetails = []
        playlist = []
        resetShufflePool()
        playOrigin = .unknown
        isMiniVisible = false
        presentExpanded = false
        isAdvancingTrack = false
        lastProgressSentAt = 0
        lastStatsPosition = 0
        pendingStatsSeconds = 0
        lastPlayedMediaID = ""
        lastPlayedQueue = ""
        lastPlayedOriginType = ""
        lastPlayedOriginName = ""
        NowPlayingManager.clear()
    }
}
