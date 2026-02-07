import SwiftUI

struct ExploreView: View {
    @StateObject private var viewModel = ExploreViewModel()
    @EnvironmentObject private var auth: AuthViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(hex: "0f1216"), Color(hex: "0b0d10")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        filterChips

                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else if let error = viewModel.errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(viewModel.items) { item in
                                    NavigationLink(value: item) {
                                        MediaCard(item: item)
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
            .navigationDestination(for: MediaItem.self) { item in
                PlayerView(mediaID: item.id, autoPlay: false)
            }
            .task {
                if viewModel.items.isEmpty {
                    await viewModel.load()
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Explore")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Online Sync")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "9aa3ab"))
                }
            }

            Spacer()

            NavigationLink {
                FavoritesGroupsView()
            } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }

            Menu {
                if let user = auth.user {
                    Text(user.displayName)
                    if let email = user.email {
                        Text(email)
                    }
                }
                Button("Sign Out", role: .destructive) {
                    auth.signOut()
                }
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ExploreViewModel.Filter.allCases) { filter in
                    Button {
                        Task { await viewModel.refreshForFilter(filter) }
                    } label: {
                        ChipView(title: filter.rawValue, isSelected: viewModel.selectedFilter == filter)
                    }
                }
            }
        }
    }
}

#Preview {
    ExploreView()
        .environmentObject(AuthViewModel())
}
