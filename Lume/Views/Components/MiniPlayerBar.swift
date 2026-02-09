import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var viewModel: PlayerViewModel

    var body: some View {
        let hasDetail = viewModel.detail != nil

        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.detail?.title ?? "尚未播放")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "22252a"))
                    .lineLimit(1)

                Text(hasDetail ? "Now Playing" : "选择一首歌开始")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "7c8188"))
            }

            Spacer()

            Button {
                viewModel.togglePlay()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: "1c1f24"))
                    .frame(width: 34, height: 34)
                    .background(Color.white)
                    .clipShape(Circle())
                    .opacity(hasDetail ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!hasDetail)

            Button {
                viewModel.presentExpanded = true
                viewModel.isMiniVisible = false
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "1c1f24"))
                    .frame(width: 34, height: 34)
                    .background(Color.white)
                    .clipShape(Circle())
                    .opacity(hasDetail ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!hasDetail)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasDetail else { return }
            viewModel.presentExpanded = true
            viewModel.isMiniVisible = false
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.08))

            if let detail = viewModel.detail {
                CachedAsyncImage(url: detail.thumbURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.black.opacity(0.2)
                        .overlay(
                            Image(systemName: detail.type == .audio ? "music.note" : "film")
                                .foregroundStyle(Color.black.opacity(0.6))
                        )
                }
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(Color.black.opacity(0.5))
            }
        }
        .frame(width: 50, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    MiniPlayerBar()
        .environmentObject(PlayerViewModel())
}
