import SwiftUI

struct FavoritesGroupsView: View {
    @StateObject private var viewModel = FavoriteGroupsViewModel()
    @State private var showCreateSheet = false

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
                    HStack {
                        Text("Favorites")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)

                        Spacer()

                        Button {
                            showCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.groups) { group in
                                NavigationLink {
                                    FavoritesListView(group: group)
                                } label: {
                                    FavoriteGroupRow(group: group)
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await viewModel.deleteGroup(id: group.id) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
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
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateFavoriteGroupSheet { name, type in
                Task { await viewModel.createGroup(name: name, mediaType: type) }
            }
        }
    }
}

private struct FavoriteGroupRow: View {
    let group: FavoriteGroup

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: group.mediaType == .audio ? "music.note" : "film")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(group.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                Text("\(group.count) items · \(group.mediaType == .audio ? "Audio" : "Video")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct CreateFavoriteGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var mediaType: MediaType = .audio

    let onCreate: (String, MediaType) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    TextField("Group Name", text: $name)
                }

                Section("Type") {
                    Picker("Type", selection: $mediaType) {
                        Text("Audio").tag(MediaType.audio)
                        Text("Video").tag(MediaType.video)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("New Group")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name, mediaType)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FavoritesGroupsView()
    }
}
