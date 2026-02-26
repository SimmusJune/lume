import Combine
import Foundation

@MainActor
final class FavoriteGroupsViewModel: ObservableObject {
    @Published var groups: [FavoriteGroup] = []
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
            async let loadedGroups = api.fetchFavoriteGroups()
            async let unfavoritedItems = api.fetchUnfavoritedAudioItems()

            let favoriteGroups = try await loadedGroups
            let unfavoritedAudioItems = try await unfavoritedItems
            let unfavoritedCount = unfavoritedAudioItems.count

            groups = [FavoriteGroup.unfavoritedAudioGroup(count: unfavoritedCount)] + favoriteGroups
        } catch {
            errorMessage = "Failed to load favorites."
        }
        isLoading = false
    }

    func createGroup(name: String, mediaType: MediaType) async {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            _ = try await api.createFavoriteGroup(name: name, mediaType: mediaType)
            await load()
        } catch {
            errorMessage = "Failed to create group."
        }
    }

    func deleteGroup(id: String) async {
        guard id != FavoriteGroup.unfavoritedAudioGroupID else { return }
        do {
            try await api.deleteFavoriteGroup(id: id)
            await load()
        } catch {
            errorMessage = "Failed to delete group."
        }
    }
}
