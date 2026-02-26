import Combine
import Foundation

@MainActor
final class FavoriteListViewModel: ObservableObject {
    let group: FavoriteGroup
    var supportsEditing: Bool { !group.isUnfavoritedAudioGroup }

    @Published var items: [FavoriteListItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api: APIClient

    init(group: FavoriteGroup, api: APIClient = .shared) {
        self.group = group
        self.api = api
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            if group.isUnfavoritedAudioGroup {
                items = try await api.fetchUnfavoritedAudioItems()
            } else {
                let response = try await api.fetchFavoriteItems(groupID: group.id)
                items = response.items
            }
        } catch {
            errorMessage = "Failed to load favorites."
        }
        isLoading = false
    }

    func remove(mediaID: String) async {
        guard supportsEditing else { return }
        do {
            try await api.removeFavoriteItem(groupID: group.id, mediaID: mediaID)
            items.removeAll { $0.mediaID == mediaID }
        } catch {
            errorMessage = "Failed to remove item."
        }
    }

    func persistOrder() async {
        guard supportsEditing else { return }
        do {
            try await api.reorderFavoriteItems(groupID: group.id, orderedMediaIDs: items.map(\.mediaID))
        } catch {
            errorMessage = "Failed to reorder favorites."
            await load()
        }
    }
}
