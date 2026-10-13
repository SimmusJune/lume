import Foundation

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
}

final class APIClient {
    static let shared = APIClient()
    static let didDeleteMedia = Notification.Name("APIClientDidDeleteMedia")
    static let didUpdateMedia = Notification.Name("APIClientDidUpdateMedia")
    static let didChangeFamilyLibrary = Notification.Name("APIClientDidChangeFamilyLibrary")
    static let didSwitchLibrary = Notification.Name("APIClientDidSwitchLibrary")

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
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
        let report = try await library.importJSON(from: url)
        await PlaybackStatsStore.shared.reloadFromStorage()
        await SpacedRepetitionStore.shared.reloadFromStorage()
        await FamilySharingManager.shared.libraryDidChange()
        await FamilySharingManager.shared.playbackDidChange(immediate: true)
        await FamilySharingManager.shared.allReviewStatesDidChange()
        return report
    }

    func exportJSONFile() async throws -> URL {
        let playbackStats = await PlaybackStatsStore.shared.displayedSnapshot()
        let reviewStates = await SpacedRepetitionStore.shared.currentSnapshot()
        let data = try await library.exportJSON(playbackStats: playbackStats, reviewStates: reviewStates)
        let timestamp = Self.exportDateFormatter.string(from: Date())
        let fileName = "lume-library-\(timestamp).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])
        return url
    }

    func deleteMedia(id: String) async throws {
        try await library.deleteMedia(id: id)
        await SpacedRepetitionStore.shared.remove(mediaID: id)
        await FamilySharingManager.shared.libraryDidChange()
        NotificationCenter.default.post(name: Self.didDeleteMedia, object: id)
    }

    func updateMedia(id: String, title: String, subtitle: String?, tags: [String]?) async throws {
        try await library.updateMedia(id: id, title: title, subtitle: subtitle, tags: tags)
        await FamilySharingManager.shared.libraryDidChange()
        NotificationCenter.default.post(name: Self.didUpdateMedia, object: id)
    }

    func postProgress(id: String, positionMS: Int, event: String? = nil) async throws {
        await FamilySharingManager.shared.progressDidChange(mediaID: id, positionMS: positionMS, event: event)
    }

    func fetchFavoriteGroups() async throws -> [FavoriteGroup] {
        await library.listGroups()
    }

    func createFavoriteGroup(name: String, mediaType: MediaType) async throws -> FavoriteGroup {
        let group = try await library.createGroup(name: name, mediaType: mediaType)
        await FamilySharingManager.shared.libraryDidChange()
        return group
    }

    func deleteFavoriteGroup(id: String) async throws {
        try await library.deleteGroup(id: id)
        await FamilySharingManager.shared.libraryDidChange()
    }

    func fetchFavoriteItems(groupID: String, page: Int = 1, pageSize: Int = 50) async throws -> FavoriteListResponse {
        let items = await library.listItems(groupID: groupID)
        return FavoriteListResponse(page: page, pageSize: items.count, total: items.count, items: items)
    }

    func addFavoriteItem(groupID: String, mediaID: String) async throws -> FavoriteListItem {
        let item = try await library.addItem(groupID: groupID, mediaID: mediaID)
        await FamilySharingManager.shared.libraryDidChange()
        return item
    }

    func removeFavoriteItem(groupID: String, mediaID: String) async throws {
        try await library.removeItem(groupID: groupID, mediaID: mediaID)
        await FamilySharingManager.shared.libraryDidChange()
    }

    func reorderFavoriteItems(groupID: String, orderedMediaIDs: [String]) async throws {
        try await library.reorderItems(groupID: groupID, orderedMediaIDs: orderedMediaIDs)
        await FamilySharingManager.shared.libraryDidChange()
    }

    func fetchUnfavoritedAudioItems() async throws -> [FavoriteListItem] {
        async let mediaResponse = fetchMediaList(type: .audio, keyword: nil)
        async let groups = fetchFavoriteGroups()

        let allAudioResponse = try await mediaResponse
        let allAudioItems = allAudioResponse.items
        let favoriteGroups = try await groups
        let audioGroupIDs = favoriteGroups
            .filter { $0.mediaType == .audio && !$0.isUnfavoritedAudioGroup }
            .map(\.id)

        let favoritedAudioIDs = try await withThrowingTaskGroup(of: [String].self) { group in
            for groupID in audioGroupIDs {
                group.addTask { [self] in
                    let response = try await fetchFavoriteItems(groupID: groupID)
                    return response.items
                        .filter { $0.mediaType == .audio }
                        .map(\.mediaID)
                }
            }

            var ids = Set<String>()
            for try await mediaIDs in group {
                ids.formUnion(mediaIDs)
            }
            return ids
        }

        return allAudioItems
            .filter { !favoritedAudioIDs.contains($0.id) }
            .map { item in
                FavoriteListItem(
                    id: item.id,
                    mediaID: item.id,
                    mediaType: item.type,
                    title: item.title,
                    subtitle: nil,
                    durationMS: item.durationMS,
                    thumbURL: item.thumbURL,
                    tags: item.tags
                )
            }
    }
}
