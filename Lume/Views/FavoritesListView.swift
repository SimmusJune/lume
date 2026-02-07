import SwiftUI

struct FavoritesListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FavoriteListViewModel

    init(group: FavoriteGroup) {
        _viewModel = StateObject(wrappedValue: FavoriteListViewModel(group: group))
    }

    var body: some View {
        ZStack {
            Color(hex: "f3f5f6")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        quickActions

                        HStack {
                            Text("\(viewModel.items.count) items")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(hex: "22252a"))

                            Spacer()

                            HStack(spacing: 12) {
                                IconChip(systemName: "bolt.fill")
                                IconChip(systemName: "arrow.down.to.line")
                                IconChip(systemName: "list.bullet")
                                IconChip(systemName: "ellipsis")
                            }
                        }

                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else if let error = viewModel.errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                        } else {
                            let playlist = viewModel.items.map(\.mediaID)
                            LazyVStack(spacing: 12) {
                                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                                    HStack(alignment: .top, spacing: 12) {
                                        NavigationLink {
                                            PlayerView(mediaID: item.mediaID, autoPlay: true, playlist: playlist)
                                        } label: {
                                            FavoriteItemContent(index: index + 1, item: item)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)

                                        Spacer()

                                        FavoriteItemActions {
                                            Task { await viewModel.remove(mediaID: item.mediaID) }
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "22252a"))
                    .frame(width: 36, height: 36)
                    .background(Color.white)
                    .clipShape(Circle())
            }

            Spacer()

            Text(viewModel.group.name)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: "22252a"))

            Spacer()

            Button {
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "22252a"))
                    .frame(width: 36, height: 36)
                    .background(Color.white)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color(hex: "f3f5f6"))
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            ActionPill(systemName: "heart.fill", title: "收藏歌单")
            ActionPill(systemName: "play.fill", title: "全部播放")
        }
    }
}

private struct FavoriteItemContent: View {
    let index: Int
    let item: FavoriteListItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: "33373d"))
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "22252a"))

                    if let tags = item.tags {
                        ForEach(tags.prefix(2), id: \.self) { tag in
                            TagChip(title: tag)
                        }
                    }
                }

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "7c8188"))
                } else {
                    Text(item.mediaType == .audio ? "Audio" : "Video")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "7c8188"))
                }
            }

        }
    }
}

private struct FavoriteItemActions: View {
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button {
                onRemove()
            } label: {
                Image(systemName: "heart")
            }

            Button {
            } label: {
                Image(systemName: "plus")
            }

            Button {
            } label: {
                Image(systemName: "ellipsis")
            }
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Color(hex: "7c8188"))
    }
}

private struct TagChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(hex: "a96b1f"))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(hex: "f6e9d4"))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ActionPill: View {
    let systemName: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Color(hex: "1c1f24"))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

private struct IconChip: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(hex: "33373d"))
            .frame(width: 30, height: 30)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

#Preview {
    NavigationStack {
        FavoritesListView(group: FavoriteGroup(id: "g_audio", name: "corazon 的每日 30 首", mediaType: .audio, count: 30))
    }
    .environmentObject(PlayerViewModel())
}
