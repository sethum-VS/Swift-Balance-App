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
    @Published var isOfflineMode: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var canResendVerificationEmail: Bool = false
    @Published var isLoading: Bool = false

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                if let user {
                    let requiresVerification = Self.requiresEmailVerification(for: user)
                    let isVerifiedSession = !requiresVerification || user.isEmailVerified
                    self?.isAuthenticated = isVerifiedSession
                    self?.canResendVerificationEmail = requiresVerification && !user.isEmailVerified

                    if isVerifiedSession {
                        self?.errorMessage = nil
                        self?.successMessage = nil
                    }
                } else {
                    self?.isAuthenticated = false
                    self?.canResendVerificationEmail = false
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
            successMessage = nil
            return
        }

        errorMessage = nil
        successMessage = nil
        canResendVerificationEmail = false
        isLoading = true

        Auth.auth().signIn(withEmail: trimmedEmail, password: password) { [weak self] authResult, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error {
                    self?.isAuthenticated = false
                    self?.canResendVerificationEmail = false
                    self?.errorMessage = error.localizedDescription
                    return
                }

                guard let user = Auth.auth().currentUser ?? authResult?.user else {
                    self?.isAuthenticated = false
                    self?.canResendVerificationEmail = false
                    self?.errorMessage = "Unable to validate your account."
                    return
                }

                guard !Self.requiresEmailVerification(for: user) || user.isEmailVerified else {
                    self?.isAuthenticated = false
                    self?.canResendVerificationEmail = true
                    self?.successMessage = nil
                    self?.errorMessage = "Please verify your email before signing in."
                    return
                }

                self?.isAuthenticated = true
                self?.canResendVerificationEmail = false
                self?.errorMessage = nil
                self?.successMessage = nil
            }
        }
    }

    @MainActor
    func signUp(email: String, password: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required."
            successMessage = nil
            return
        }

        errorMessage = nil
        successMessage = nil
        canResendVerificationEmail = false
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
            successMessage = nil
        } catch {
            isAuthenticated = false
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    @MainActor
    func resetPassword(email: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Enter your email first to reset your password."
            successMessage = nil
            return
        }

        errorMessage = nil
        successMessage = nil
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            try await Auth.auth().sendPasswordReset(withEmail: trimmedEmail)
            successMessage = "Reset link sent to your email."
        } catch {
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    @MainActor
    func resendVerificationEmail() async {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Please sign in again before requesting a verification email."
            successMessage = nil
            canResendVerificationEmail = false
            return
        }

        errorMessage = nil
        successMessage = nil
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            try await Auth.auth().currentUser?.sendEmailVerification()
            successMessage = "Verification email sent. Please check your inbox."
        } catch {
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    @MainActor
    func signInWithGoogle() async {
        errorMessage = nil
        successMessage = nil
        canResendVerificationEmail = false
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                isAuthenticated = false
                errorMessage = "Google Sign-In is not configured."
                successMessage = nil
                return
            }

            guard let presentingViewController = Self.topViewController() else {
                isAuthenticated = false
                errorMessage = "Unable to present Google Sign-In."
                successMessage = nil
                return
            }

            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)

            guard let idToken = signInResult.user.idToken?.tokenString else {
                isAuthenticated = false
                errorMessage = "Google ID token is missing."
                successMessage = nil
                return
            }

            let accessToken = signInResult.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

            _ = try await Auth.auth().signIn(with: credential)
            isAuthenticated = true
            errorMessage = nil
            successMessage = nil
        } catch {
            isAuthenticated = false
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    func signOut() {
        isOfflineMode = false
        if (try? Auth.auth().signOut()) != nil {
            isAuthenticated = false
            canResendVerificationEmail = false
            errorMessage = nil
            successMessage = nil
            NotificationCenter.default.post(name: .userDidSignOut, object: nil)
        } else {
            // If no Firebase user (guest mode), just reset state
            if Auth.auth().currentUser == nil {
                isAuthenticated = false
                canResendVerificationEmail = false
                errorMessage = nil
                successMessage = nil
                NotificationCenter.default.post(name: .userDidSignOut, object: nil)
            } else {
                errorMessage = "Failed to sign out."
                successMessage = nil
            }
        }
    }

    /// Enters offline "Guest" mode — bypasses login without creating a Firebase session.
    func continueOffline() {
        isOfflineMode = true
        isAuthenticated = true
        errorMessage = nil
        successMessage = nil
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
