import SwiftUI

struct RootView: View {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var playback = PlayerViewModel()

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

            if playback.isMiniVisible, playback.detail != nil {
                MiniPlayerBar()
                    .environmentObject(playback)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .onChange(of: auth.identityToken) { token in
            APIClient.shared.authorizationToken = token
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
