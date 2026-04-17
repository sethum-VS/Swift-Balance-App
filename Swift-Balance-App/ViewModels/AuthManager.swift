//
//  AuthManager.swift
//  Swift-Balance-App
//
//  Created by GitHub Copilot on 2026-04-14.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

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
                if let user {
                    let requiresVerification = Self.requiresEmailVerification(for: user)
                    self?.isAuthenticated = !requiresVerification || user.isEmailVerified

                    if self?.isAuthenticated == true {
                        self?.errorMessage = nil
                    }
                } else {
                    self?.isAuthenticated = false
                }

                if user != nil, self?.isAuthenticated == true {
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

                guard let user = Auth.auth().currentUser ?? authResult?.user else {
                    self?.isAuthenticated = false
                    self?.errorMessage = "Unable to validate your account."
                    return
                }

                guard !Self.requiresEmailVerification(for: user) || user.isEmailVerified else {
                    try? Auth.auth().signOut()
                    self?.isAuthenticated = false
                    self?.errorMessage = "Please verify your email before signing in."
                    return
                }

                self?.isAuthenticated = true
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
            let authResult = try await Auth.auth().createUser(withEmail: trimmedEmail, password: password)
            try await authResult.user.sendEmailVerification()
            try? Auth.auth().signOut()

            isAuthenticated = false
            errorMessage = "Account created. Please check your email and verify your account before signing in."
        } catch {
            isAuthenticated = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func signInWithGoogle() async {
        errorMessage = nil
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                isAuthenticated = false
                errorMessage = "Google Sign-In is not configured."
                return
            }

            guard let presentingViewController = Self.topViewController() else {
                isAuthenticated = false
                errorMessage = "Unable to present Google Sign-In."
                return
            }

            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)

            guard let idToken = signInResult.user.idToken?.tokenString else {
                isAuthenticated = false
                errorMessage = "Google ID token is missing."
                return
            }

            let accessToken = signInResult.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

            _ = try await Auth.auth().signIn(with: credential)
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

    private static func requiresEmailVerification(for user: User) -> Bool {
        user.providerData.contains { $0.providerID == EmailAuthProviderID }
    }

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let startingViewController: UIViewController? = {
            if let base {
                return base
            }

            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?
                .rootViewController
        }()

        if let navigationController = startingViewController as? UINavigationController {
            return topViewController(base: navigationController.visibleViewController)
        }

        if let tabBarController = startingViewController as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return topViewController(base: selectedViewController)
        }

        if let presentedViewController = startingViewController?.presentedViewController {
            return topViewController(base: presentedViewController)
        }

        return startingViewController
    }
}
