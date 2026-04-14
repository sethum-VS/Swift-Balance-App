//
//  AuthManager.swift
//  Swift-Balance-App
//
//  Created by GitHub Copilot on 2026-04-14.
//

import Foundation
import FirebaseAuth

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

    func signOut() {
        do {
            try Auth.auth().signOut()
            isAuthenticated = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
