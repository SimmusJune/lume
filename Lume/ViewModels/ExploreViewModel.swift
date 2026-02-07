import Combine
import Foundation

@MainActor
final class ExploreViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case videos = "Videos"
        case music = "Music"
        case favorites = "Favorites"
        case recent = "Recent"

        var id: String { rawValue }

        var mediaType: MediaType? {
            switch self {
            case .videos: return .video
            case .music: return .audio
            default: return nil
            }
        }
    }

    @Published var items: [MediaItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFilter: Filter = .all

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await api.fetchMediaList(type: selectedFilter.mediaType, keyword: nil)
            items = response.items
        } catch {
            errorMessage = "Failed to load media."
        }
        isLoading = false
    }

    func refreshForFilter(_ filter: Filter) async {
        selectedFilter = filter
        await load()
    }
}
