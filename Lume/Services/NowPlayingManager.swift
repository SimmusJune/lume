import Foundation
import MediaPlayer
import UIKit

enum NowPlayingManager {
    private static var cachedArtwork: [URL: MPMediaItemArtwork] = [:]
    private static var lastArtworkURL: URL?

    static func updateMetadata(detail: MediaDetail, elapsed: Double, duration: Double, isPlaying: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = detail.title
        info[MPMediaItemPropertyArtist] = detail.subtitle ?? "Lume"
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let url = detail.thumbURL {
            setArtwork(url: url)
        }
    }

    static func updatePlayback(elapsed: Double, duration: Double, isPlaying: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    static func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private static func setArtwork(url: URL) {
        if lastArtworkURL == url, cachedArtwork[url] != nil {
            return
        }
        lastArtworkURL = url

        if let artwork = cachedArtwork[url] {
            applyArtwork(artwork)
            return
        }

        Task.detached {
            if let image = await ImageCache.shared.image(for: url) {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                cachedArtwork[url] = artwork
                await MainActor.run {
                    applyArtwork(artwork)
                }
            }
        }
    }

    private static func applyArtwork(_ artwork: MPMediaItemArtwork) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
