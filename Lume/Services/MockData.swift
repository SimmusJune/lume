import Foundation

enum MockData {
    static let items: [MediaItem] = buildItems()

    static func listResponse() -> MediaListResponse {
        MediaListResponse(page: 1, pageSize: items.count, total: items.count, items: items)
    }

    static func detail(for id: String) -> MediaDetail {
        let item = items.first { $0.id == id } ?? items[0]
        let sources: [MediaSource]

        if item.type == .video {
            sources = [
                MediaSource(
                    format: "mp4",
                    quality: "source",
                    url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!
                )
            ]
        } else {
            sources = [
                MediaSource(
                    format: "mp3",
                    quality: "source",
                    url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")!
                )
            ]
        }

        return MediaDetail(
            id: item.id,
            type: item.type,
            title: item.title,
            durationMS: item.durationMS,
            status: item.status,
            thumbURL: item.thumbURL,
            sources: sources
        )
    }

    private static func buildItems() -> [MediaItem] {
        let adjectives = [
            "Midnight", "Solar", "Neon", "Silent", "Crystal",
            "Golden", "Lunar", "Velvet", "Radiant", "Echoing",
            "Aero", "Pacific", "Ivory", "Magnetic", "Nova",
            "Glacial", "Crimson", "Cosmic", "Prism", "Aurora"
        ]
        let nouns = [
            "Serenade", "Rift", "Drift", "Signal", "Echo",
            "Voyage", "Pulse", "Tide", "Dream", "Canvas",
            "Orbit", "Harvest", "Bloom", "Circuit", "Mirage",
            "Horizon", "Atlas", "Runner", "Spectrum", "Vortex"
        ]

        var result: [MediaItem] = []
        result.reserveCapacity(100)

        for index in 1...100 {
            let type: MediaType = index % 2 == 0 ? .audio : .video
            let adjective = adjectives[index % adjectives.count]
            let noun = nouns[(index * 3) % nouns.count]
            let title = "\(adjective) \(noun)"
            let seconds = 90 + (index * 37 % 240)
            let durationMS = seconds * 1000
            let id = String(format: "m_%03d", index)
            let thumbURL = URL(string: "https://picsum.photos/seed/lume\(index)/600/600")

            result.append(
                MediaItem(
                    id: id,
                    type: type,
                    title: title,
                    durationMS: durationMS,
                    thumbURL: thumbURL,
                    status: "ready",
                    tags: nil
                )
            )
        }

        return result
    }
}
