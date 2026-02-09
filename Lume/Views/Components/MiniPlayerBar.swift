import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var viewModel: PlayerViewModel

    var body: some View {
        if let detail = viewModel.detail {
            HStack(spacing: 12) {
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
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "22252a"))
                        .lineLimit(1)

                    Text("Now Playing")
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
                }

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
                }
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
                viewModel.presentExpanded = true
                viewModel.isMiniVisible = false
            }
        }
    }
}

#Preview {
    MiniPlayerBar()
        .environmentObject(PlayerViewModel())
}
