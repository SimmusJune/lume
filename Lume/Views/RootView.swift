import SwiftUI

struct RootView: View {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var playback = PlayerViewModel()
    @StateObject private var updateGate = UpdateGateViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if auth.isSignedIn {
                    ExploreView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(auth)
            .environmentObject(playback)
            .safeAreaInset(edge: .bottom) {
                if playback.isMiniVisible {
                    Color.clear.frame(height: 78)
                }
            }

            if playback.isMiniVisible {
                MiniPlayerBar()
                    .environmentObject(playback)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            if let forceUpdate = updateGate.forceUpdate {
                ForceUpdateView(
                    state: forceUpdate,
                    onUpdate: { updateGate.openUpdatePage() },
                    onRetry: { Task { await updateGate.refresh() } }
                )
            }
        }
        .onChange(of: auth.identityToken) { token in
            APIClient.shared.authorizationToken = token
        }
        .onChange(of: auth.user) { _ in
            playback.isMiniVisible = auth.isSignedIn
            if auth.isSignedIn {
                Task { await playback.restoreLastPlayedIfNeeded(autoPlay: true) }
            }
        }
        .onAppear {
            if auth.isSignedIn {
                playback.isMiniVisible = true
                Task { await playback.restoreLastPlayedIfNeeded(autoPlay: true) }
            }
            Task { await updateGate.refresh() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background || phase == .active {
                if playback.isPlaying {
                    AudioSessionManager.configurePlayback()
                }
                if phase == .active {
                    Task { await updateGate.refresh() }
                }
            }
        }
        .sheet(isPresented: $playback.presentExpanded) {
            if let detail = playback.detail {
                PlayerView(mediaID: detail.id, autoPlay: false)
                    .environmentObject(playback)
            } else {
                Text("Loading...")
            }
        }
    }
}

private struct ForceUpdateView: View {
    let state: ForceUpdateState
    let onUpdate: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)

                Text(state.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                Text(state.message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)

                Button(action: onUpdate) {
                    Text(state.buttonTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button(action: onRetry) {
                    Text("Retry")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    RootView()
}
