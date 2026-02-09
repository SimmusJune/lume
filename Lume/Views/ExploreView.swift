import SwiftUI
import UniformTypeIdentifiers

struct ExploreView: View {
    @StateObject private var viewModel = ExploreViewModel()
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var playback: PlayerViewModel
    @State private var showImporter = false
    @AppStorage("lume.adminModeEnabled") private var isAdminMode = false
    @State private var pendingDelete: MediaItem?
    @State private var showDeleteAlert = false

    private let rowSpacing: CGFloat = 12

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(hex: "0f1216"), Color(hex: "0b0d10")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        filterChips
                        searchBar
                        if let summary = viewModel.importSummary {
                            Text(summary)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: "9aa3ab"))
                        }
                        if isAdminMode {
                            Text("Admin mode enabled")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: "ffb957"))
                        }

                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else if let error = viewModel.errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                        } else if viewModel.items.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: rowSpacing) {
                                ForEach(viewModel.items) { item in
                                    ZStack(alignment: .topTrailing) {
                                        Button {
                                            play(item: item, playlist: viewModel.items.map(\.id))
                                        } label: {
                                            MediaCard(item: item)
                                        }
                                        .buttonStyle(.plain)

                                        if isAdminMode {
                                            Button {
                                                pendingDelete = item
                                                showDeleteAlert = true
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundStyle(Color.white)
                                                    .frame(width: 28, height: 28)
                                                    .background(Color.red.opacity(0.85))
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.plain)
                                            .padding(8)
                                            .zIndex(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationDestination(for: MediaItem.self) { item in
                PlayerView(mediaID: item.id, autoPlay: false, playlist: viewModel.items.map(\.id))
            }
            .task {
                if viewModel.items.isEmpty {
                    await viewModel.load()
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await viewModel.importJSON(from: url) }
                case .failure:
                    viewModel.errorMessage = "Failed to import JSON."
                }
            }
            .alert("Delete media?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let item = pendingDelete {
                        Task { await viewModel.deleteMedia(item) }
                    }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDelete = nil
                }
            } message: {
                if let title = pendingDelete?.title, !title.isEmpty {
                    Text("This will remove \"\(title)\" from your local library.")
                } else {
                    Text("This will remove the media from your local library.")
                }
            }
        }
    }

    private func play(item: MediaItem, playlist: [String]) {
        playback.setQueue(ids: playlist, currentID: item.id)
        Task {
            await playback.load(id: item.id, autoPlay: true)
            playback.isMiniVisible = true
            playback.presentExpanded = false
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Explore")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: "9dff85"))
                        .frame(width: 8, height: 8)
                    Text("Local Library")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "9aa3ab"))
                }
            }
            .simultaneousGesture(
                TapGesture(count: 5)
                    .onEnded {
                        isAdminMode.toggle()
                    }
            )

            Spacer()

            NavigationLink {
                FavoritesGroupsView()
            } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            NavigationLink {
                TagPlaylistsView()
            } label: {
                Image(systemName: "music.note.list")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                showImporter = true
            } label: {
                Image(systemName: "tray.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }

            NavigationLink {
                ProfileView()
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ExploreViewModel.Filter.allCases) { filter in
                    Button {
                        Task { await viewModel.refreshForFilter(filter) }
                    } label: {
                        ChipView(title: filter.rawValue, isSelected: viewModel.selectedFilter == filter)
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))

            TextField("Search", text: $viewModel.searchText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    Task { await viewModel.load() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .onChange(of: viewModel.searchText) { _ in
            Task { await viewModel.load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No media imported yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Text("Import a JSON file to build your local library.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "9aa3ab"))

            Button {
                showImporter = true
            } label: {
                Text("Import JSON")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "0b0d10"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: "9dff85"))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

#Preview {
    ExploreView()
        .environmentObject(AuthViewModel())
}
