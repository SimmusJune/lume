import SwiftUI
import UniformTypeIdentifiers

struct ExploreView: View {
    @StateObject private var viewModel = ExploreViewModel()
    @StateObject private var favoritesViewModel = FavoriteGroupsViewModel()
    @StateObject private var playlistsViewModel = TagPlaylistsViewModel()
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var playback: PlayerViewModel
    @State private var showImporter = false
    @AppStorage("lume.adminModeEnabled") private var isAdminMode = false
    @State private var pendingDelete: MediaItem?
    @State private var showDeleteAlert = false
    @State private var favoriteTarget: MediaItem?
    @State private var showFavoritesList = false
    @State private var showPlaylistsList = false
    @State private var showCreateFavoriteSheet = false
    @State private var selectedFavoriteGroup: FavoriteGroup?
    @State private var selectedTagGroup: TagPlaylistsViewModel.TagGroup?

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
                        if showFavoritesList {
                            favoritesSection
                        }
                        if showPlaylistsList {
                            playlistsSection
                        }
                        if !showFavoritesList && !showPlaylistsList {
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
                                            MediaCard(item: item, onFavorite: {
                                                favoriteTarget = item
                                            })
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                play(item: item, playlist: viewModel.items.map(\.id))
                                            }

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
            .sheet(item: $favoriteTarget) { item in
                FavoritesPickerSheet(mediaID: item.id, mediaType: item.type)
            }
            .navigationDestination(item: $selectedFavoriteGroup) { group in
                FavoritesListView(group: group)
            }
            .navigationDestination(item: $selectedTagGroup) { group in
                ExploreTagPlaylistDetailView(tag: group.tag, items: group.items)
            }
            .sheet(isPresented: $showCreateFavoriteSheet) {
                CreateFavoriteGroupSheet { name, type in
                    Task { await favoritesViewModel.createGroup(name: name, mediaType: type) }
                }
            }
            .onChange(of: showFavoritesList) { isShown in
                guard isShown, favoritesViewModel.groups.isEmpty, !favoritesViewModel.isLoading else { return }
                Task { await favoritesViewModel.load() }
            }
            .onChange(of: showPlaylistsList) { isShown in
                guard isShown, playlistsViewModel.groups.isEmpty, !playlistsViewModel.isLoading else { return }
                Task { await playlistsViewModel.load() }
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
                        showFavoritesList = false
                        showPlaylistsList = false
                        Task { await viewModel.refreshForFilter(filter) }
                    } label: {
                        ChipView(
                            title: filter.rawValue,
                            isSelected: !showFavoritesList && !showPlaylistsList && viewModel.selectedFilter == filter
                        )
                    }
                }

                Button {
                    showFavoritesList.toggle()
                    if showFavoritesList {
                        showPlaylistsList = false
                    }
                } label: {
                    ChipView(title: "收藏", isSelected: showFavoritesList)
                }
                .buttonStyle(.plain)

                Button {
                    showPlaylistsList.toggle()
                    if showPlaylistsList {
                        showFavoritesList = false
                    }
                } label: {
                    ChipView(title: "歌单", isSelected: showPlaylistsList)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("收藏")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    showCreateFavoriteSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if favoritesViewModel.isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else if let error = favoritesViewModel.errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            } else if favoritesViewModel.groups.isEmpty {
                Text("暂无收藏")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "9aa3ab"))
            } else {
                VStack(spacing: 10) {
                    ForEach(favoritesViewModel.groups) { group in
                        Button {
                            selectedFavoriteGroup = group
                        } label: {
                            ExploreFavoriteGroupRow(group: group)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await favoritesViewModel.deleteGroup(id: group.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("歌单")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            if playlistsViewModel.isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else if let error = playlistsViewModel.errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            } else if playlistsViewModel.groups.isEmpty {
                Text("暂无歌单")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "9aa3ab"))
            } else {
                VStack(spacing: 10) {
                    ForEach(playlistsViewModel.groups) { group in
                        Button {
                            selectedTagGroup = group
                        } label: {
                            ExploreTagRow(tag: group.tag, count: group.items.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 4)
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

private struct ExploreFavoriteGroupRow: View {
    let group: FavoriteGroup

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: group.mediaType == .audio ? "music.note" : "film")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(group.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text("\(group.count) items · \(group.mediaType == .audio ? "Audio" : "Video")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct ExploreTagRow: View {
    let tag: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tag)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text("\(count) tracks")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct ExploreTagPlaylistDetailView: View {
    let tag: String
    let items: [MediaItem]
    @EnvironmentObject private var playback: PlayerViewModel
    @State private var favoriteTarget: MediaItem?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(hex: "0f1216"), Color(hex: "0b0d10")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(tag)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            MediaCard(item: item, onFavorite: {
                                favoriteTarget = item
                            })
                            .contentShape(Rectangle())
                            .onTapGesture {
                                play(item: item, playlist: items.map(\.id))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .sheet(item: $favoriteTarget) { item in
            FavoritesPickerSheet(mediaID: item.id, mediaType: item.type)
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
}

private struct CreateFavoriteGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var mediaType: MediaType = .audio

    let onCreate: (String, MediaType) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    TextField("Group Name", text: $name)
                }

                Section("Type") {
                    Picker("Type", selection: $mediaType) {
                        Text("Audio").tag(MediaType.audio)
                        Text("Video").tag(MediaType.video)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("New Group")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name, mediaType)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ExploreView()
        .environmentObject(AuthViewModel())
}
