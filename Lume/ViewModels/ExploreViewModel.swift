import Combine
import Foundation

@MainActor
final class ExploreViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case videos = "Videos"
        case music = "Music"

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
    @Published var importSummary: String?
    @Published var selectedFilter: Filter = .all
    @Published var searchText: String = ""

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await api.fetchMediaList(
                type: selectedFilter.mediaType,
                keyword: keyword.isEmpty ? nil : keyword
            )
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

    func importJSON(from url: URL) async {
        isLoading = true
        errorMessage = nil
        importSummary = nil
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let report = try await api.importJSON(url: url)
            let response = try await api.fetchMediaList(type: selectedFilter.mediaType, keyword: nil)
            items = response.items
            importSummary = "Imported \(report.inserted) new, updated \(report.updated), skipped \(report.skipped)."
        } catch {
            errorMessage = "Failed to import JSON."
        }
        isLoading = false
    }

    func deleteMedia(_ item: MediaItem) async {
        isLoading = true
        errorMessage = nil
        do {
            try await api.deleteMedia(id: item.id)
            let response = try await api.fetchMediaList(type: selectedFilter.mediaType, keyword: nil)
            items = response.items
        } catch {
            errorMessage = "Failed to delete media."
        }
        isLoading = false
    }
}
