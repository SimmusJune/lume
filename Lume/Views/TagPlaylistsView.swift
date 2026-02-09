import SwiftUI

struct TagPlaylistsView: View {
    @StateObject private var viewModel = TagPlaylistsViewModel()

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
                    Text("Playlists")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                    } else if viewModel.groups.isEmpty {
                        Text("No audio playlists yet.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "9aa3ab"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.groups) { group in
                                NavigationLink {
                                    TagPlaylistDetailView(tag: group.tag, items: group.items)
                                } label: {
                                    TagRow(tag: group.tag, count: group.items.count)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

private struct TagRow: View {
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

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct TagPlaylistDetailView: View {
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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

#Preview {
    TagPlaylistsView()
        .environmentObject(AuthViewModel())
        .environmentObject(PlayerViewModel())
}
