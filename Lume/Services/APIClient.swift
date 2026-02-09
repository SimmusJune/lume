import Foundation

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
}

final class APIClient {
    static let shared = APIClient()

    var authorizationToken: String?

    private let library: LocalLibraryStore
    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    init(library: LocalLibraryStore = .shared) {
        self.library = library
    }

    func fetchMediaList(type: MediaType?, keyword: String?, page: Int = 1, pageSize: Int = 20) async throws -> MediaListResponse {
        let items = await library.listMedia(type: type, keyword: keyword)
        return MediaListResponse(page: page, pageSize: items.count, total: items.count, items: items)
    }

    func fetchMediaDetail(id: String) async throws -> MediaDetail {
        try await library.mediaDetail(id: id)
    }

    func importJSON(url: URL) async throws -> ImportReport {
        try await library.importJSON(from: url)
    }

    func exportJSONFile() async throws -> URL {
        let data = try await library.exportJSON()
        let timestamp = Self.exportDateFormatter.string(from: Date())
        let fileName = "lume-library-\(timestamp).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])
        return url
    }

    func deleteMedia(id: String) async throws {
        try await library.deleteMedia(id: id)
    }

    func postProgress(id: String, positionMS: Int, event: String? = nil) async throws {
        _ = (id, positionMS, event)
    }

    func fetchFavoriteGroups() async throws -> [FavoriteGroup] {
        await library.listGroups()
    }

    func createFavoriteGroup(name: String, mediaType: MediaType) async throws -> FavoriteGroup {
        try await library.createGroup(name: name, mediaType: mediaType)
    }

    func deleteFavoriteGroup(id: String) async throws {
        try await library.deleteGroup(id: id)
    }

    func fetchFavoriteItems(groupID: String, page: Int = 1, pageSize: Int = 50) async throws -> FavoriteListResponse {
        let items = await library.listItems(groupID: groupID)
        return FavoriteListResponse(page: page, pageSize: items.count, total: items.count, items: items)
    }

    func addFavoriteItem(groupID: String, mediaID: String) async throws -> FavoriteListItem {
        try await library.addItem(groupID: groupID, mediaID: mediaID)
    }

    func removeFavoriteItem(groupID: String, mediaID: String) async throws {
        try await library.removeItem(groupID: groupID, mediaID: mediaID)
    }

}
