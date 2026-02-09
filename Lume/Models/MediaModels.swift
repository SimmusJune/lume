import Foundation

enum MediaType: String, Codable, CaseIterable {
    case audio
    case video
}

struct MediaItem: Identifiable, Codable, Hashable {
    let id: String
    let type: MediaType
    let title: String
    let durationMS: Int
    let thumbURL: URL?
    let status: String
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case durationMS = "duration_ms"
        case thumbURL = "thumb_url"
        case status
        case tags
    }
}

struct MediaListResponse: Codable {
    let page: Int
    let pageSize: Int
    let total: Int
    let items: [MediaItem]

    enum CodingKeys: String, CodingKey {
        case page
        case pageSize = "page_size"
        case total
        case items
    }
}

struct MediaSource: Codable, Hashable {
    let format: String
    let quality: String
    let url: URL
}

struct MediaDetail: Identifiable, Codable, Hashable {
    let id: String
    let type: MediaType
    let title: String
    let subtitle: String?
    let durationMS: Int
    let status: String
    let thumbURL: URL?
    let sources: [MediaSource]

    init(id: String, type: MediaType, title: String, subtitle: String? = nil, durationMS: Int, status: String, thumbURL: URL?, sources: [MediaSource]) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.durationMS = durationMS
        self.status = status
        self.thumbURL = thumbURL
        self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case subtitle
        case durationMS = "duration_ms"
        case status
        case thumbURL = "thumb_url"
        case sources
    }
}

struct ProgressPayload: Codable {
    let positionMS: Int
    let event: String?

    enum CodingKeys: String, CodingKey {
        case positionMS = "position_ms"
        case event
    }
}
