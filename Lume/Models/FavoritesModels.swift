import Foundation

struct FavoriteGroup: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let mediaType: MediaType
    let count: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mediaType = "media_type"
        case count
    }
}

struct FavoriteGroupsResponse: Codable {
    let items: [FavoriteGroup]
}

struct FavoriteListItem: Identifiable, Codable, Hashable {
    let id: String
    let mediaID: String
    let mediaType: MediaType
    let title: String
    let subtitle: String?
    let durationMS: Int
    let thumbURL: URL?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case mediaID = "media_id"
        case mediaType = "media_type"
        case title
        case subtitle
        case durationMS = "duration_ms"
        case thumbURL = "thumb_url"
        case tags
    }
}

struct FavoriteListResponse: Codable {
    let page: Int
    let pageSize: Int
    let total: Int
    let items: [FavoriteListItem]

    enum CodingKeys: String, CodingKey {
        case page
        case pageSize = "page_size"
        case total
        case items
    }
}

struct CreateFavoriteGroupPayload: Codable {
    let name: String
    let mediaType: MediaType

    enum CodingKeys: String, CodingKey {
        case name
        case mediaType = "media_type"
    }
}

struct AddFavoriteItemPayload: Codable {
    let mediaID: String

    enum CodingKeys: String, CodingKey {
        case mediaID = "media_id"
    }
}
