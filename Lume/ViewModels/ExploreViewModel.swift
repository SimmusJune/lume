import Combine
import Foundation

@MainActor
final class ExploreViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case music = "Music"

        static var visibleCases: [Filter] {
            [.all, .music]
        }

        var id: String { rawValue }

        var mediaType: MediaType? {
            switch self {
            case .music: return .audio
            case .all: return nil
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
            items = visibleItems(from: response.items)
        } catch {
            errorMessage = "Failed to load media."
        }
        isLoading = false
    }

    func refreshForFilter(_ filter: Filter) async {
        selectedFilter = filter
        await load()
    }

    func fetchLibraryQueueIDs() async -> [String] {
        do {
            let response = try await api.fetchMediaList(type: selectedFilter.mediaType, keyword: nil)
            return visibleItems(from: response.items).map(\.id)
        } catch {
            return []
        }
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
            items = visibleItems(from: response.items)
            importSummary = report.didImportPlaybackStats
                ? "Imported \(report.inserted) new, updated \(report.updated), skipped \(report.skipped), and restored playback stats."
                : "Imported \(report.inserted) new, updated \(report.updated), skipped \(report.skipped)."
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
            items = visibleItems(from: response.items)
        } catch {
            errorMessage = "Failed to delete media."
        }
        isLoading = false
    }

    private func visibleItems(from items: [MediaItem]) -> [MediaItem] {
        items.filter { $0.type != .video }
    }
}
