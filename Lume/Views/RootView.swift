import SwiftUI

struct RootView: View {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var playback = PlayerViewModel()
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
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background || phase == .active {
                if playback.isPlaying {
                    AudioSessionManager.configurePlayback()
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

#Preview {
    RootView()
}
