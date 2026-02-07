import Combine
import Foundation

@MainActor
final class FavoriteListViewModel: ObservableObject {
    let group: FavoriteGroup

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
            let response = try await api.fetchFavoriteItems(groupID: group.id)
            items = response.items
        } catch {
            errorMessage = "Failed to load favorites."
        }
        isLoading = false
    }

    func remove(mediaID: String) async {
        do {
            try await api.removeFavoriteItem(groupID: group.id, mediaID: mediaID)
            items.removeAll { $0.mediaID == mediaID }
        } catch {
            errorMessage = "Failed to remove item."
        }
    }
}
