import CryptoKit
import Foundation

actor AudioCache {
    static let shared = AudioCache()
    static let didCacheAudio = Notification.Name("AudioCacheDidStore")

    private let fileManager: FileManager
    private let cacheDirectory: URL
    private var inFlight: [String: Task<URL, Error>] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            self.cacheDirectory = dir.appendingPathComponent("AudioCache", isDirectory: true)
        } else {
            self.cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("AudioCache", isDirectory: true)
        }
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cachedURLIfNeeded(source: MediaSource, mediaType: MediaType, mediaID: String?) async -> URL {
        guard mediaType == .audio else { return source.url }
        guard !source.url.isFileURL else { return source.url }
        if source.format.lowercased() == "m3u8" {
            return source.url
        }

        let key = cacheKey(for: source.url, mediaID: mediaID)
        if let task = inFlight[key] {
            return (try? await task.value) ?? source.url
        }

        let fileURL = cacheDirectory.appendingPathComponent(fileName(for: source.url), isDirectory: false)
        let task = Task { [fileManager, cacheDirectory] () throws -> URL in
            if fileManager.fileExists(atPath: fileURL.path) {
                return fileURL
            }
            let (tempURL, response) = try await URLSession.shared.download(from: source.url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
            try fileManager.moveItem(at: tempURL, to: fileURL)
            NotificationCenter.default.post(name: AudioCache.didCacheAudio, object: source.url)
            return fileURL
        }

        inFlight[key] = task
        do {
            let url = try await task.value
            inFlight[key] = nil
            return url
        } catch {
            inFlight[key] = nil
            return source.url
        }
    }

    func isCached(url: URL) -> Bool {
        let fileURL = cacheDirectory.appendingPathComponent(fileName(for: url), isDirectory: false)
        return fileManager.fileExists(atPath: fileURL.path)
    }

    private func cacheKey(for url: URL, mediaID: String?) -> String {
        if let mediaID, !mediaID.isEmpty {
            return "\(mediaID)-\(url.absoluteString)"
        }
        return url.absoluteString
    }

    private func fileName(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        return "\(hex).\(ext)"
    }
}
