import Foundation
import Combine

@MainActor
final class TagPlaylistsViewModel: ObservableObject {
    struct TagGroup: Identifiable, Hashable {
        let id: String
        let tag: String
        let items: [MediaItem]

        static func == (lhs: TagGroup, rhs: TagGroup) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    /// 没有 tag 的曲目会归到这个分组下。
    static let untaggedGroupName = "Untagged"

    @Published var groups: [TagGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await api.fetchMediaList(type: .audio, keyword: nil)
            groups = buildGroups(from: response.items)
        } catch {
            errorMessage = "Failed to load playlists."
        }
        isLoading = false
    }

    private func buildGroups(from items: [MediaItem]) -> [TagGroup] {
        var grouped: [String: [MediaItem]] = [:]

        for item in items {
            let tags = Self.normalizedTags(item.tags)
            if tags.isEmpty {
                grouped[Self.untaggedGroupName, default: []].append(item)
            } else {
                for tag in tags {
                    grouped[tag, default: []].append(item)
                }
            }
        }

        let sortedTags = grouped.keys.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        return sortedTags.map { tag in
            TagGroup(id: tag, tag: tag, items: grouped[tag] ?? [])
        }
    }

    /// 某个曲目是否属于指定分组。改完标签后各详情页用它重新判定成员，
    /// 这样编辑后加进来的、被移出去的曲目都能立刻反映出来。
    static func belongsToGroup(_ item: MediaItem, tag: String) -> Bool {
        let tags = normalizedTags(item.tags)
        if tags.isEmpty { return tag == untaggedGroupName }
        return tags.contains(tag)
    }

    private static func normalizedTags(_ tags: [String]?) -> [String] {
        guard let tags else { return [] }
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
