import AuthenticationServices
import Combine
import Foundation
import SwiftUI

struct AuthUser: Equatable {
    let id: String
    let displayName: String
    let email: String?
}

@MainActor
final class AuthViewModel: ObservableObject {
    @AppStorage("appleUserID") private var storedUserID = ""
    @AppStorage("appleUserName") private var storedUserName = ""
    @AppStorage("appleUserEmail") private var storedUserEmail = ""

    @Published private(set) var user: AuthUser?
    @Published private(set) var identityToken: String?
    @Published var errorMessage: String?

    var isSignedIn: Bool {
        user != nil
    }

    init() {
        if !storedUserID.isEmpty {
            user = AuthUser(id: storedUserID, displayName: storedUserName, email: storedUserEmail.isEmpty ? nil : storedUserEmail)
        }
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Invalid Apple ID credential."
                return
            }

            let displayName = formatName(credential.fullName) ?? storedUserName
            let email = credential.email ?? (storedUserEmail.isEmpty ? nil : storedUserEmail)

            storedUserID = credential.user
            storedUserName = displayName
            storedUserEmail = email ?? ""

            if let tokenData = credential.identityToken {
                identityToken = String(data: tokenData, encoding: .utf8)
            }

            user = AuthUser(id: credential.user, displayName: displayName, email: email)
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func demoSignIn() {
        user = AuthUser(id: "demo", displayName: "Demo User", email: nil)
        errorMessage = nil
    }

    func signOut() {
        storedUserID = ""
        storedUserName = ""
        storedUserEmail = ""
        identityToken = nil
        user = nil
    }

    private func formatName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        let name = formatter.string(from: components)
        return name.isEmpty ? nil : name
    }
}
