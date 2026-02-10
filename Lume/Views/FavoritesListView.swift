import SwiftUI

struct FavoritesListView: View {
    @EnvironmentObject private var playback: PlayerViewModel
    @StateObject private var viewModel: FavoriteListViewModel

    init(group: FavoriteGroup) {
        _viewModel = StateObject(wrappedValue: FavoriteListViewModel(group: group))
    }

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
                    Text(viewModel.group.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if viewModel.items.isEmpty {
                        Text("暂无收藏")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "9aa3ab"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        let playlist = viewModel.items.map(\.mediaID)
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.items) { item in
                                MediaCard(item: mediaItem(from: item), onFavorite: {
                                    Task { await viewModel.remove(mediaID: item.mediaID) }
                                })
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    play(item: item, playlist: playlist)
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
        .background(NavigationPopGestureDisabled())
        .task {
            await viewModel.load()
        }
    }

    private func play(item: FavoriteListItem, playlist: [String]) {
        playback.setQueue(ids: playlist, currentID: item.mediaID, origin: .favorites(name: viewModel.group.name))
        Task {
            await playback.load(id: item.mediaID, autoPlay: true)
            playback.isMiniVisible = true
            playback.presentExpanded = false
        }
    }

    private func mediaItem(from item: FavoriteListItem) -> MediaItem {
        MediaItem(
            id: item.mediaID,
            type: item.mediaType,
            title: item.title,
            durationMS: item.durationMS,
            thumbURL: item.thumbURL,
            status: "",
            tags: item.tags
        )
    }
}

private struct NavigationPopGestureDisabled: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.isDisabled = true
    }

    final class Controller: UIViewController {
        var isDisabled: Bool = true {
            didSet { updateGesture() }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updateGesture()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        private func updateGesture() {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = !isDisabled
        }
    }
}

#Preview {
    NavigationStack {
        FavoritesListView(group: FavoriteGroup(id: "g_audio", name: "corazon 的每日 30 首", mediaType: .audio, count: 30))
    }
    .environmentObject(PlayerViewModel())
}
