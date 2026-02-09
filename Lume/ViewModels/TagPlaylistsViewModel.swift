import Foundation
import Combine

@MainActor
final class TagPlaylistsViewModel: ObservableObject {
    struct TagGroup: Identifiable {
        let id: String
        let tag: String
        let items: [MediaItem]
    }

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
            let tags = normalizedTags(item.tags)
            if tags.isEmpty {
                grouped["Untagged", default: []].append(item)
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

    private func normalizedTags(_ tags: [String]?) -> [String] {
        guard let tags else { return [] }
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
