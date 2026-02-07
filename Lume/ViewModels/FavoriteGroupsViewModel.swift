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
            groups = try await api.fetchFavoriteGroups()
        } catch {
            errorMessage = "Failed to load favorites."
        }
        isLoading = false
    }

    func createGroup(name: String, mediaType: MediaType) async {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let group = try await api.createFavoriteGroup(name: name, mediaType: mediaType)
            groups.insert(group, at: 0)
        } catch {
            errorMessage = "Failed to create group."
        }
    }

    func deleteGroup(id: String) async {
        do {
            try await api.deleteFavoriteGroup(id: id)
            groups.removeAll { $0.id == id }
        } catch {
            errorMessage = "Failed to delete group."
        }
    }
}
