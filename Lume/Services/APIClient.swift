import Foundation

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
}

final class APIClient {
    static let shared = APIClient()

    var baseURL = AppConfig.baseURL
    var useMockData = AppConfig.useMockData
    var authorizationToken: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchMediaList(type: MediaType?, keyword: String?, page: Int = 1, pageSize: Int = 20) async throws -> MediaListResponse {
        if useMockData {
            try await Task.sleep(nanoseconds: 250_000_000)
            let response = MockData.listResponse()
            if let type {
                let filtered = response.items.filter { $0.type == type }
                return MediaListResponse(page: 1, pageSize: pageSize, total: filtered.count, items: filtered)
            }
            return response
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/media"), resolvingAgainstBaseURL: false)
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize))
        ]
        if let type {
            query.append(URLQueryItem(name: "type", value: type.rawValue))
        }
        if let keyword, !keyword.isEmpty {
            query.append(URLQueryItem(name: "keyword", value: keyword))
        }
        components?.queryItems = query
        guard let url = components?.url else { throw APIError.invalidURL }

        let request = makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(MediaListResponse.self, from: data)
    }

    func fetchMediaDetail(id: String) async throws -> MediaDetail {
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            return MockData.detail(for: id)
        }
        let url = baseURL.appendingPathComponent("/api/media/\(id)")
        let request = makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(MediaDetail.self, from: data)
    }

    func postProgress(id: String, positionMS: Int, event: String? = nil) async throws {
        if useMockData { return }
        let url = baseURL.appendingPathComponent("/api/media/\(id)/progress")
        var request = makeRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ProgressPayload(positionMS: positionMS, event: event))

        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    func fetchFavoriteGroups() async throws -> [FavoriteGroup] {
        if useMockData {
            try await Task.sleep(nanoseconds: 120_000_000)
            return await MockStore.shared.listGroups()
        }
        let url = baseURL.appendingPathComponent("/api/favorites/groups")
        let request = makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(FavoriteGroupsResponse.self, from: data).items
    }

    func createFavoriteGroup(name: String, mediaType: MediaType) async throws -> FavoriteGroup {
        if useMockData {
            try await Task.sleep(nanoseconds: 120_000_000)
            return await MockStore.shared.createGroup(name: name, mediaType: mediaType)
        }
        let url = baseURL.appendingPathComponent("/api/favorites/groups")
        var request = makeRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CreateFavoriteGroupPayload(name: name, mediaType: mediaType))

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(FavoriteGroup.self, from: data)
    }

    func deleteFavoriteGroup(id: String) async throws {
        if useMockData {
            await MockStore.shared.deleteGroup(id: id)
            return
        }
        let url = baseURL.appendingPathComponent("/api/favorites/groups/\(id)")
        var request = makeRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    func fetchFavoriteItems(groupID: String, page: Int = 1, pageSize: Int = 50) async throws -> FavoriteListResponse {
        if useMockData {
            try await Task.sleep(nanoseconds: 120_000_000)
            let items = await MockStore.shared.listItems(groupID: groupID)
            return FavoriteListResponse(page: 1, pageSize: pageSize, total: items.count, items: items)
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/favorites/groups/\(groupID)/items"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize))
        ]
        guard let url = components?.url else { throw APIError.invalidURL }
        let request = makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(FavoriteListResponse.self, from: data)
    }

    func addFavoriteItem(groupID: String, mediaID: String) async throws -> FavoriteListItem {
        if useMockData {
            try await Task.sleep(nanoseconds: 120_000_000)
            return try await MockStore.shared.addItem(groupID: groupID, mediaID: mediaID)
        }
        let url = baseURL.appendingPathComponent("/api/favorites/groups/\(groupID)/items")
        var request = makeRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AddFavoriteItemPayload(mediaID: mediaID))

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(FavoriteListItem.self, from: data)
    }

    func removeFavoriteItem(groupID: String, mediaID: String) async throws {
        if useMockData {
            await MockStore.shared.removeItem(groupID: groupID, mediaID: mediaID)
            return
        }
        let url = baseURL.appendingPathComponent("/api/favorites/groups/\(groupID)/items/\(mediaID)")
        var request = makeRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let authorizationToken {
            request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }
    }
}
