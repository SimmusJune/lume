import SwiftUI

struct FavoritesPickerSheet: View {
    let mediaID: String
    let mediaType: MediaType

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FavoriteGroupsViewModel()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.groups.filter { $0.mediaType == mediaType }) { group in
                        Button {
                            Task { await add(to: group) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name)
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("\(group.count) items")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(mediaType == .audio ? "Audio Groups" : "Video Groups")
                }
            }
            .navigationTitle("Add to Favorites")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await viewModel.load()
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func add(to group: FavoriteGroup) async {
        do {
            _ = try await APIClient.shared.addFavoriteItem(groupID: group.id, mediaID: mediaID)
            dismiss()
        } catch {
            errorMessage = "Could not add to this group."
        }
    }
}

#Preview {
    FavoritesPickerSheet(mediaID: "m_001", mediaType: .audio)
}
