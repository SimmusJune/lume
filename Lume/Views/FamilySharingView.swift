import CloudKit
import SwiftUI
import UIKit

struct FamilySharingView: View {
    @ObservedObject private var family = FamilySharingManager.shared
    @State private var newFamilyName = "Family Library"
    @State private var showInvitation = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(hex: "0f1216"), Color(hex: "0b0d10")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if family.isUsingFamily {
                        activeFamilyContent
                    } else {
                        inactiveFamilyContent
                    }
                    if let message = family.errorMessage {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Family Library")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showInvitation) {
            if let share = family.shareRecord {
                FamilyCloudSharingSheet(share: share)
            }
        }
    }

    private var activeFamilyContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(family.familyName ?? "Family Library", systemImage: "person.3.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Text("Songs, favorites, listening history, play counts, listening time, and review progress are shared with members. Each device can keep playing while offline and sync later.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.7))

            if let lastSync = family.lastSyncAt {
                Text("Last synced \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            if family.isOwner {
                actionButton("Invite Family Members", symbol: "person.badge.plus") {
                    showInvitation = true
                }
                .disabled(family.shareRecord == nil)
            }

            actionButton(family.isSyncing ? "Syncing…" : "Sync Now", symbol: "arrow.triangle.2.circlepath") {
                Task { await family.refresh() }
            }
            .disabled(family.isSyncing)

            Button("Use Personal Library") {
                Task { await family.usePersonalLibrary() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.7))
        }
    }

    private var inactiveFamilyContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Share one library with your family")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Text("Everyone uses their own iCloud account. Create a family library, then invite members with an iCloud sharing link.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.7))

            if family.hasSavedFamily {
                actionButton("Return to Family Library", symbol: "person.3.fill") {
                    Task {
                        do { try await family.resumeFamily() }
                        catch { family.errorMessage = error.localizedDescription }
                    }
                }
            } else {
                TextField("Family name", text: $newFamilyName)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)

                actionButton("Create Family Library", symbol: "plus.circle.fill") {
                    Task {
                        do {
                            try await family.createFamily(name: newFamilyName)
                            showInvitation = family.shareRecord != nil
                        } catch {
                            family.errorMessage = error.localizedDescription
                        }
                    }
                }
            }

            Text("To join, open the invitation link sent by the family owner on this device.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .disabled(family.isBusy)
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct FamilyCloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer.default())
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(share: share) }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let share: CKShare

        init(share: CKShare) { self.share = share }

        func itemTitle(for controller: UICloudSharingController) -> String? {
            share[CKShare.SystemFieldKey.title] as? String
        }

        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: Error) {
            FamilySharingManager.shared.errorMessage = error.localizedDescription
        }
    }
}
