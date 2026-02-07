import Foundation

actor MockStore {
    static let shared = MockStore()

    private var groups: [FavoriteGroup] = []
    private var itemsByGroup: [String: [FavoriteListItem]] = [:]

    init() {
        seedIfNeeded()
    }

    func listGroups() -> [FavoriteGroup] {
        groups.map { group in
            let count = itemsByGroup[group.id]?.count ?? 0
            return FavoriteGroup(id: group.id, name: group.name, mediaType: group.mediaType, count: count)
        }
    }

    func listItems(groupID: String) -> [FavoriteListItem] {
        itemsByGroup[groupID] ?? []
    }

    func createGroup(name: String, mediaType: MediaType) -> FavoriteGroup {
        let id = "g_\(UUID().uuidString.prefix(8))"
        let group = FavoriteGroup(id: id, name: name, mediaType: mediaType, count: 0)
        groups.append(group)
        itemsByGroup[id] = []
        return group
    }

    func deleteGroup(id: String) {
        groups.removeAll { $0.id == id }
        itemsByGroup[id] = nil
    }

    func addItem(groupID: String, mediaID: String) throws -> FavoriteListItem {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else {
            throw APIError.httpStatus(404)
        }
        let group = groups[groupIndex]
        guard let media = MockData.items.first(where: { $0.id == mediaID }) else {
            throw APIError.httpStatus(404)
        }
        guard media.type == group.mediaType else {
            throw APIError.httpStatus(409)
        }

        var items = itemsByGroup[groupID] ?? []
        if let existing = items.first(where: { $0.mediaID == mediaID }) {
            return existing
        }

        let item = buildFavoriteItem(from: media)
        items.insert(item, at: 0)
        itemsByGroup[groupID] = items
        return item
    }

    func removeItem(groupID: String, mediaID: String) {
        guard var items = itemsByGroup[groupID] else { return }
        items.removeAll { $0.mediaID == mediaID }
        itemsByGroup[groupID] = items
    }

    func isFavorite(mediaID: String) -> String? {
        for (groupID, items) in itemsByGroup where items.contains(where: { $0.mediaID == mediaID }) {
            return groupID
        }
        return nil
    }

    func moveItem(mediaID: String, fromGroupID: String, toGroupID: String) throws {
        guard let toGroup = groups.first(where: { $0.id == toGroupID }) else {
            throw APIError.httpStatus(404)
        }
        guard let media = MockData.items.first(where: { $0.id == mediaID }) else {
            throw APIError.httpStatus(404)
        }
        guard media.type == toGroup.mediaType else {
            throw APIError.httpStatus(409)
        }

        removeItem(groupID: fromGroupID, mediaID: mediaID)
        _ = try addItem(groupID: toGroupID, mediaID: mediaID)
    }

    private func seedIfNeeded() {
        guard groups.isEmpty else { return }
        let audioGroup = FavoriteGroup(id: "g_audio", name: "My Audios", mediaType: .audio, count: 0)
        let videoGroup = FavoriteGroup(id: "g_video", name: "My Videos", mediaType: .video, count: 0)
        groups = [audioGroup, videoGroup]

        let audioItems = MockData.items.filter { $0.type == .audio }.prefix(30)
        let videoItems = MockData.items.filter { $0.type == .video }.prefix(20)
        itemsByGroup[audioGroup.id] = audioItems.map { buildFavoriteItem(from: $0) }
        itemsByGroup[videoGroup.id] = videoItems.map { buildFavoriteItem(from: $0) }
    }

    private func buildFavoriteItem(from media: MediaItem) -> FavoriteListItem {
        let index = mediaIndex(from: media.id)
        let creator = creators[index % creators.count]
        let tags = tagsForIndex(index, type: media.type)
        return FavoriteListItem(
            id: media.id,
            mediaID: media.id,
            mediaType: media.type,
            title: media.title,
            subtitle: creator,
            durationMS: media.durationMS,
            thumbURL: media.thumbURL,
            tags: tags
        )
    }

    private func mediaIndex(from id: String) -> Int {
        let digits = id.split(separator: "_").last ?? "0"
        return Int(digits) ?? 0
    }

    private var creators: [String] {
        [
            "Luna Echoes", "Ken Blast", "Auroa Dive", "Jilly", "Nova Drift",
            "Mira Lane", "Echo Bloom", "Orbit Nine", "Solstice", "Velvet Sky"
        ]
    }

    private func tagsForIndex(_ index: Int, type: MediaType) -> [String] {
        let audioTags = ["VIP", "DTS:X", "Live", "HQ", "Chill"]
        let videoTags = ["4K", "HDR", "IMAX", "Director", "Remaster"]
        let source = type == .audio ? audioTags : videoTags
        let first = source[index % source.count]
        let second = source[(index * 3) % source.count]
        return Array(Set([first, second])).sorted()
    }
}
