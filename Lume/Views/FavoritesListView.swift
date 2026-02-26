import SwiftUI
import UniformTypeIdentifiers

struct FavoritesListView: View {
    @EnvironmentObject private var playback: PlayerViewModel
    @StateObject private var viewModel: FavoriteListViewModel
    @State private var draggedItem: FavoriteListItem?
    @State private var favoriteTarget: MediaItem?

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
                                if viewModel.supportsEditing {
                                    MediaCard(item: mediaItem(from: item), onFavorite: {
                                        Task { await viewModel.remove(mediaID: item.mediaID) }
                                    })
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        play(item: item, playlist: playlist)
                                    }
                                    .opacity(draggedItem?.id == item.id ? 0.65 : 1)
                                    .onDrag {
                                        draggedItem = item
                                        return NSItemProvider(object: item.mediaID as NSString)
                                    }
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: FavoriteItemDropDelegate(
                                            item: item,
                                            items: $viewModel.items,
                                            draggedItem: $draggedItem,
                                            onCommit: persistOrder
                                        )
                                    )
                                } else {
                                    MediaCard(item: mediaItem(from: item), onFavorite: {
                                        favoriteTarget = mediaItem(from: item)
                                    })
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        play(item: item, playlist: playlist)
                                    }
                                }
                            }
                        }
                        .animation(.easeInOut(duration: 0.18), value: viewModel.items)
                        .onDrop(
                            of: [UTType.text],
                            delegate: FavoritesListDropDelegate(
                                items: $viewModel.items,
                                draggedItem: $draggedItem,
                                onCommit: persistOrder,
                                isEnabled: viewModel.supportsEditing
                            )
                        )
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
        .sheet(item: $favoriteTarget, onDismiss: {
            Task { await viewModel.load() }
        }) { item in
            FavoritesPickerSheet(mediaID: item.id, mediaType: item.type)
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

    private func persistOrder(_ orderedMediaIDs: [String]) {
        guard orderedMediaIDs == viewModel.items.map(\.mediaID) else { return }
        Task { await viewModel.persistOrder() }
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

private struct FavoriteItemDropDelegate: DropDelegate {
    let item: FavoriteListItem
    @Binding var items: [FavoriteListItem]
    @Binding var draggedItem: FavoriteListItem?
    let onCommit: ([String]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedItem, draggedItem != item else { return }
        guard let fromIndex = items.firstIndex(of: draggedItem),
              let toIndex = items.firstIndex(of: item) else { return }
        guard fromIndex != toIndex else { return }

        withAnimation {
            items.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        onCommit(items.map(\.mediaID))
        return true
    }
}

private struct FavoritesListDropDelegate: DropDelegate {
    @Binding var items: [FavoriteListItem]
    @Binding var draggedItem: FavoriteListItem?
    let onCommit: ([String]) -> Void
    let isEnabled: Bool

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isEnabled else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isEnabled else { return false }
        draggedItem = nil
        onCommit(items.map(\.mediaID))
        return true
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
