import SwiftUI

struct ChipView: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isSelected ? Color.black : Color(hex: "cdd3d8"))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color(hex: "9dff85") : Color.white.opacity(0.06))
            )
    }
}

struct MediaCard: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 10) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if item.type == .audio {
                        AudioCacheBadge(sourceID: item.id)
                    }

                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(item.type == .audio ? "Music" : "Video")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)

                    Text(durationText(item.durationMS))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
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

    private struct AudioCacheBadge: View {
        let sourceID: String
        private let url: URL?
        @State private var isCached: Bool?

        init(sourceID: String) {
            self.sourceID = sourceID
            self.url = Self.normalizedURL(from: sourceID)
        }

        var body: some View {
            Group {
                if isCached == true {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: "9dff85"))
                } else {
                    Image(systemName: "cloud")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .task(id: sourceID) { await refresh() }
            .onReceive(NotificationCenter.default.publisher(for: AudioCache.didCacheAudio)) { notification in
                guard let cachedURL = notification.object as? URL else { return }
                guard cachedURL == url else { return }
                Task { await refresh() }
            }
        }

        private func refresh() async {
            guard let url else {
                await MainActor.run { isCached = nil }
                return
            }
            let cached = await AudioCache.shared.isCached(url: url)
            await MainActor.run { isCached = cached }
        }

        private static func normalizedURL(from raw: String) -> URL? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if let url = URL(string: trimmed) {
                return url
            }
            if let escaped = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
                return URL(string: escaped)
            }
            return nil
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(0.08))
                .frame(width: 48, height: 48)

            CachedAsyncImage(url: item.thumbURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(systemName: item.type == .audio ? "music.note" : "film")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 9))

        }
    }

    private func durationText(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
