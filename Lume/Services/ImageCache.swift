import CryptoKit
import Foundation
import UIKit

actor ImageCache {
    static let shared = ImageCache()

    private let fileManager: FileManager
    private let cacheDirectory: URL
    private let memoryCache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            self.cacheDirectory = dir.appendingPathComponent("ImageCache", isDirectory: true)
        } else {
            self.cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ImageCache", isDirectory: true)
        }
        memoryCache.countLimit = 200
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }
        if let disk = loadFromDisk(url) {
            memoryCache.setObject(disk, forKey: url as NSURL)
            return disk
        }
        if let task = inFlight[url] {
            return await task.value
        }
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.downloadAndStore(url)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }

    private func loadFromDisk(_ url: URL) -> UIImage? {
        let fileURL = cacheDirectory.appendingPathComponent(fileName(for: url), isDirectory: false)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    private func downloadAndStore(_ url: URL) async -> UIImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let image = UIImage(data: data) else { return nil }
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let fileURL = cacheDirectory.appendingPathComponent(fileName(for: url), isDirectory: false)
            try? data.write(to: fileURL, options: .atomic)
            memoryCache.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
    }

    private func fileName(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
        return "\(hex).\(ext)"
    }
}
