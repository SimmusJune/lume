import AVKit
import SwiftUI

struct PlayerView: View {
    let mediaID: String
    let autoPlay: Bool
    let playlist: [String]?

    init(mediaID: String, autoPlay: Bool, playlist: [String]? = nil) {
        self.mediaID = mediaID
        self.autoPlay = autoPlay
        self.playlist = playlist
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: PlayerViewModel
    @State private var showFavoritesPicker = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "f7cba6"), Color(hex: "f9e2c8"), Color(hex: "f6f2ec")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                topBar

                // pageDots

                mediaHero

                titleSection

                progressSection

                playbackControls

                Spacer(minLength: 12)
            }
            .offset(y: dragOffset)
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .task {
            await viewModel.load(id: mediaID, autoPlay: autoPlay)
        }
        .onAppear {
            viewModel.isMiniVisible = false
            if let playlist {
                viewModel.setQueue(ids: playlist, currentID: mediaID)
            }
        }
        .onDisappear {
            if viewModel.detail != nil {
                viewModel.isMiniVisible = true
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        viewModel.collapseToMini()
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .sheet(isPresented: $showFavoritesPicker) {
            if let detail = viewModel.detail {
                FavoritesPickerSheet(mediaID: detail.id, mediaType: detail.type)
            } else {
                Text("Loading...")
                    .presentationDetents([.medium])
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                viewModel.collapseToMini()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .foregroundStyle(Color(hex: "2a2d31"))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.7))
                    .clipShape(Circle())
            }

            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "2a2d31"))
                Text("Lume")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "2a2d31"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.6))
            .clipShape(Capsule())

            Spacer()

            Button {
                showFavoritesPicker = true
            } label: {
                Image(systemName: "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "2a2d31"))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.7))
                    .clipShape(Circle())
            }

            Button {
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "2a2d31"))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.7))
                    .clipShape(Circle())
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color(hex: "2a2d31"))
                .frame(width: 14, height: 4)
            Circle()
                .fill(Color.black.opacity(0.15))
                .frame(width: 4, height: 4)
            Circle()
                .fill(Color.black.opacity(0.15))
                .frame(width: 4, height: 4)
        }
        .padding(.top, 6)
    }

    private var mediaHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.white.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.white.opacity(0.7), lineWidth: 2)
                )
                .frame(height: 320)

            if let detail = viewModel.detail, detail.type == .video {
                VideoPlayer(player: viewModel.player)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 10)
            } else {
                VinylRecordView(coverURL: viewModel.detail?.thumbURL)
                    .frame(width: 240, height: 240)
            }
        }
        .padding(.top, 8)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(viewModel.detail?.title ?? "Loading")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(hex: "2a2d31"))

                Spacer()

                Button {
                    showFavoritesPicker = true
                } label: {
                    Image(systemName: "heart")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: "2a2d31"))
                }

                Button {
                } label: {
                    Image(systemName: "heart")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: "2a2d31"))
                }
            }

            HStack(spacing: 10) {
                Text("Luna Echoes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "5e636a"))
               
            }

            Text("Rider Rider Rider of the sky")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: "7a7f86"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRow: some View {
        HStack(spacing: 30) {
            ActionIcon(systemName: "bell")
            ActionIcon(systemName: "waveform", label: "Off")
            ActionIcon(systemName: "arrow.down.to.line")
            ActionIcon(systemName: "message", label: "45")
            ActionIcon(systemName: "ellipsis")
        }
        .padding(.top, 12)
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { viewModel.positionSeconds },
                    set: { viewModel.seek(to: $0) }
                ),
                in: 0...max(1, viewModel.durationSeconds)
            )
            .tint(Color(hex: "2a2d31"))
            .padding(.horizontal, 2)

            HStack {
                Text(timeString(viewModel.positionSeconds))
                Spacer()
                Text(timeString(viewModel.durationSeconds))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(hex: "6b7077"))
        }
        .padding(.top, 6)
    }

    private var playbackControls: some View {
        HStack(spacing: 34) {
            Button {
            } label: {
                Image(systemName: "repeat")
            }

            Button {
                viewModel.previousTrack()
            } label: {
                Image(systemName: "backward.fill")
            }

            Button {
                viewModel.togglePlay()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(hex: "2a2d31"))
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .stroke(Color(hex: "2a2d31"), lineWidth: 2)
                    )
            }

            Button {
                viewModel.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
            }

            Button {
            } label: {
                Image(systemName: "list.bullet")
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Color(hex: "2a2d31"))
        .padding(.top, 6)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

private struct VinylRecordView: View {
    let coverURL: URL?

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "f7c771"), Color(hex: "f1a742")],
                        center: .center,
                        startRadius: 20,
                        endRadius: 120
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 4)
                )

            Circle()
                .fill(Color.white.opacity(0.75))
                .frame(width: 120, height: 120)
                .overlay(
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Color.black.opacity(0.1)
                        case .empty:
                            Color.black.opacity(0.05)
                        @unknown default:
                            Color.black.opacity(0.05)
                        }
                    }
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )

            ToneArmView()
                .offset(x: 90, y: -70)
        }
    }
}

private struct ToneArmView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.8))
                .frame(width: 12, height: 120)
                .rotationEffect(.degrees(20))

            Circle()
                .fill(Color.white)
                .frame(width: 26, height: 26)
                .offset(x: 18, y: -44)
        }
        .shadow(color: Color.black.opacity(0.1), radius: 6, x: 2, y: 4)
    }
}

private struct StatPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(hex: "6b7077"))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.7))
            .clipShape(Capsule())
    }
}

private struct ActionIcon: View {
    let systemName: String
    var label: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: "6b7077"))
            if let label {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "6b7077"))
            }
        }
    }
}

#Preview {
    PlayerView(mediaID: "m_123", autoPlay: false)
        .environmentObject(PlayerViewModel())
}
