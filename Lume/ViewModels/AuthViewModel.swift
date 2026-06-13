import AuthenticationServices
import Combine
import Foundation
import SwiftUI

private enum AuthProvider: String {
    case apple
    case local
}

struct AuthUser: Equatable {
    let id: String
    let displayName: String
    let email: String?
}

@MainActor
final class AuthViewModel: ObservableObject {
    private static let localUsername = "Lume"
    private static let localPassword = "Lume1228"

    @AppStorage("authProvider") private var storedAuthProvider = ""
    @AppStorage("appleUserID") private var storedUserID = ""
    @AppStorage("appleUserName") private var storedUserName = ""
    @AppStorage("appleUserEmail") private var storedUserEmail = ""
    @AppStorage("localUserName") private var storedLocalUserName = ""

    @Published private(set) var user: AuthUser?
    @Published private(set) var identityToken: String?
    @Published var errorMessage: String?

    var isSignedIn: Bool {
        user != nil
    }

    init() {
        if storedAuthProvider == AuthProvider.local.rawValue, !storedLocalUserName.isEmpty {
            user = AuthUser(id: "local:\(storedLocalUserName)", displayName: storedLocalUserName, email: nil)
        } else if !storedUserID.isEmpty {
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

            storedAuthProvider = AuthProvider.apple.rawValue
            storedUserID = credential.user
            storedUserName = displayName
            storedUserEmail = email ?? ""
            storedLocalUserName = ""

            if let tokenData = credential.identityToken {
                identityToken = String(data: tokenData, encoding: .utf8)
            }

            user = AuthUser(id: credential.user, displayName: displayName, email: email)
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func signIn(username: String, password: String) {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedUsername == Self.localUsername, trimmedPassword == Self.localPassword else {
            errorMessage = "Incorrect username or password."
            return
        }

        storedAuthProvider = AuthProvider.local.rawValue
        storedLocalUserName = trimmedUsername
        storedUserID = ""
        storedUserName = ""
        storedUserEmail = ""
        identityToken = nil
        user = AuthUser(id: "local:\(trimmedUsername)", displayName: trimmedUsername, email: nil)
        errorMessage = nil
    }

    func signOut() {
        storedAuthProvider = ""
        storedUserID = ""
        storedUserName = ""
        storedUserEmail = ""
        storedLocalUserName = ""
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
