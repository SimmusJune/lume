import AVFoundation
import Foundation
import Combine
import MediaPlayer

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var player = AVPlayer()
    @Published var detail: MediaDetail?
    @Published var isPlaying = false
    @Published var positionSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var rate: Float = 1.0
    @Published var errorMessage: String?
    @Published var isMiniVisible = false
    @Published var presentExpanded = false

    private let api: APIClient
    private var timeObserver: Any?
    private var lastProgressSentAt: Double = 0
    private var currentMediaID: String?
    private var playlist: [String] = []
    private var currentIndex: Int?
    private var remoteConfigured = false

    init(api: APIClient = .shared) {
        self.api = api
        configureRemoteCommands()
    }

    func setQueue(ids: [String], currentID: String) {
        playlist = ids
        currentIndex = ids.firstIndex(of: currentID)
    }

    func load(id: String, autoPlay: Bool) async {
        errorMessage = nil
        if currentMediaID == id, detail != nil {
            if autoPlay {
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
            let source = pickSource(from: detail.sources)
            let item = AVPlayerItem(url: source.url)
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
        NotificationCenter.default.removeObserver(self)
    }

    func nextTrack() {
        guard let index = currentIndex else { return }
        let nextIndex = index + 1
        guard nextIndex < playlist.count else { return }
        currentIndex = nextIndex
        Task { await load(id: playlist[nextIndex], autoPlay: true) }
    }

    func previousTrack() {
        if positionSeconds > 3 {
            seek(to: 0)
            return
        }
        guard let index = currentIndex else { return }
        let prevIndex = index - 1
        guard prevIndex >= 0 else { return }
        currentIndex = prevIndex
        Task { await load(id: playlist[prevIndex], autoPlay: true) }
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

        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            positionSeconds = time.seconds
            maybeSendProgress()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    @objc private func itemDidFinish() {
        isPlaying = false
        NowPlayingManager.updatePlayback(elapsed: durationSeconds, duration: durationSeconds, isPlaying: false)
        Task { await sendProgress(event: "end") }
    }

    private func maybeSendProgress() {
        let now = positionSeconds
        if now - lastProgressSentAt >= 5 {
            lastProgressSentAt = now
            Task { await sendProgress(event: nil) }
        }
        NowPlayingManager.updatePlayback(elapsed: now, duration: durationSeconds, isPlaying: isPlaying)
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
}
