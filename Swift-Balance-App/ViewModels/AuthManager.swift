//
//  AuthManager.swift
//  Swift-Balance-App
//
//  Created by GitHub Copilot on 2026-04-14.
//

import Foundation
import Combine
import FirebaseAuth

extension Notification.Name {
    static let userDidSignOut = Notification.Name("userDidSignOut")
}

enum AuthTokenError: LocalizedError {
    case userNotAuthenticated
    case tokenUnavailable

    var errorDescription: String? {
        switch self {
        case .userNotAuthenticated:
            return "User is not authenticated."
        case .tokenUnavailable:
            return "Firebase ID token unavailable."
        }
    }
}

final class AuthManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.isAuthenticated = (user != nil)
                if user != nil {
                    self?.errorMessage = nil
                }
            }
        }
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
    }

    func signIn(email: String, password: String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required."
            return
        }

        errorMessage = nil
        isLoading = true

        Auth.auth().signIn(withEmail: trimmedEmail, password: password) { [weak self] authResult, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error {
                    self?.isAuthenticated = false
                    self?.errorMessage = error.localizedDescription
                    return
                }

                self?.isAuthenticated = (authResult?.user != nil)
                self?.errorMessage = nil
            }
        }
    }

    @MainActor
    func signUp(email: String, password: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required."
            return
        }

        errorMessage = nil
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            _ = try await Auth.auth().createUser(withEmail: trimmedEmail, password: password)
            isAuthenticated = true
            errorMessage = nil
        } catch {
            isAuthenticated = false
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        if (try? Auth.auth().signOut()) != nil {
            isAuthenticated = false
            errorMessage = nil
            NotificationCenter.default.post(name: .userDidSignOut, object: nil)
        } else {
            errorMessage = "Failed to sign out."
        }
    }

    static func getIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw AuthTokenError.userNotAuthenticated
        }

        return try await withCheckedThrowingContinuation { continuation in
            user.getIDToken { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let token else {
                    continuation.resume(throwing: AuthTokenError.tokenUnavailable)
                    return
                }

                continuation.resume(returning: token)
            }
        }
    }

    func getIDToken() async throws -> String {
        try await Self.getIDToken()
    }
}
